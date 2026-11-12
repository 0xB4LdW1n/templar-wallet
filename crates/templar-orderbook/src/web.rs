use std::collections::BTreeMap;
use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use templar_core::liquid::liquidex::verify_proposal_on;
use templar_core::{LiquidNetwork, LiquidexProposal, SwapNetwork};

use crate::db::{
    validate_network, AssetInput, AssetRow, AtomicSwapCreate, AtomicSwapRow, AtomicSwapTransition,
    Database, DemoOfferRow, NewDemoOffer, NewOffer, OfferRow, OfferUpdate, REGTEST, TESTNET,
};

const DASHBOARD: &str = include_str!("dashboard.html");

pub fn router(database: Arc<Database>) -> Router {
    Router::new()
        .route("/", get(dashboard))
        .route("/api/health", get(health))
        .route("/api/book", get(book))
        .route("/api/markets", get(markets))
        .route("/api/atomic-swaps", post(create_atomic_swap))
        .route(
            "/api/atomic-swaps/{id}",
            get(get_atomic_swap).put(transition_atomic_swap),
        )
        .route("/api/admin/state", get(admin_state))
        .route("/api/admin/assets", post(upsert_asset))
        .route(
            "/api/admin/assets/{network}/{asset_id}",
            delete(delete_asset),
        )
        .route("/api/admin/offers", post(create_offer))
        .route(
            "/api/admin/offers/{id}",
            put(update_offer).delete(delete_offer),
        )
        .route("/api/admin/demo-offers", post(create_demo_offer))
        .route(
            "/api/admin/demo-offers/{id}",
            put(update_demo_offer).delete(delete_demo_offer),
        )
        .with_state(database)
}

async fn dashboard() -> impl IntoResponse {
    let mut response = Html(DASHBOARD).into_response();
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("no-store, max-age=0"),
    );
    response.headers_mut().insert(
        header::CONTENT_SECURITY_POLICY,
        HeaderValue::from_static(
            "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'",
        ),
    );
    response
}

#[derive(Serialize)]
struct HealthResponse {
    ok: bool,
    service: &'static str,
    database: String,
    networks: [&'static str; 2],
}

async fn health(State(db): State<Arc<Database>>) -> Result<Json<HealthResponse>, ApiError> {
    db.health().map_err(ApiError::internal)?;
    Ok(Json(HealthResponse {
        ok: true,
        service: "templar-orderbook",
        database: db.path().display().to_string(),
        networks: [TESTNET, REGTEST],
    }))
}

#[derive(Debug, Deserialize)]
struct BookQuery {
    #[serde(default = "default_network")]
    network: String,
    #[serde(default)]
    all: Option<String>,
}

fn default_network() -> String {
    TESTNET.to_string()
}

async fn book(
    State(db): State<Arc<Database>>,
    Query(query): Query<BookQuery>,
) -> Result<Json<BTreeMap<String, Value>>, ApiError> {
    validate_network(&query.network).map_err(ApiError::bad_request)?;
    let include_all = query.all.is_some();
    let offers = db
        .list_offers(&query.network, include_all)
        .map_err(ApiError::internal)?;
    let mut response = BTreeMap::new();
    for offer in offers {
        response.insert(offer.id.to_string(), book_entry(&offer));
    }
    Ok(Json(response))
}

fn book_entry(offer: &OfferRow) -> Value {
    let offered = display_amount(offer.offered_amount_sats, offer.offered_precision);
    let wanted = display_amount(offer.wanted_amount_sats, offer.wanted_precision);
    let offered_units = decimal_units(offer.offered_amount_sats, offer.offered_precision);
    let wanted_units = decimal_units(offer.wanted_amount_sats, offer.wanted_precision);
    let ratio = if offered_units == 0.0 {
        0.0
    } else {
        wanted_units / offered_units
    };
    json!({
        "id": offer.id,
        "available": offer.status == "open",
        "creation_timestamp": offer.created_at.to_string(),
        "ratio": ratio,
        "version": 0,
        "json": offer.proposal_json,
        "input": [{
            "amount": offered,
            "asset": offer.offered_asset_id,
            "name": format!("{} - {}", offer.offered_ticker, offer.offered_name),
            "sats": offer.offered_amount_sats,
        }],
        "output": [{
            "amount": wanted,
            "asset": offer.wanted_asset_id,
            "name": format!("{} - {}", offer.wanted_ticker, offer.wanted_name),
            "sats": offer.wanted_amount_sats,
        }],
    })
}

#[derive(Serialize)]
struct MarketLeg {
    chain: &'static str,
    network: String,
    asset_id: String,
    ticker: String,
    name: String,
    precision: u8,
    amount_sats: u64,
    display_amount: String,
}

#[derive(Serialize)]
struct MarketOffer {
    id: String,
    source_id: u64,
    status: String,
    settlement: String,
    demo: bool,
    available: bool,
    maker_gives: MarketLeg,
    maker_wants: MarketLeg,
    price_display: String,
    note: String,
    created_at: u64,
    proposal_json: String,
}

async fn markets(
    State(db): State<Arc<Database>>,
    Query(query): Query<BookQuery>,
) -> Result<Json<Vec<MarketOffer>>, ApiError> {
    validate_network(&query.network).map_err(ApiError::bad_request)?;
    let include_all = query.all.is_some();
    let liquid = db
        .list_offers(&query.network, include_all)
        .map_err(ApiError::internal)?;
    let demos = db
        .list_demo_offers(&query.network, include_all)
        .map_err(ApiError::internal)?;
    let atomic = db
        .list_atomic_swaps(&query.network, include_all)
        .map_err(ApiError::internal)?;
    let mut response = Vec::with_capacity(liquid.len() + demos.len() + atomic.len());
    response.extend(liquid.into_iter().map(liquid_market_offer));
    response.extend(demos.into_iter().map(demo_market_offer));
    response.extend(atomic.into_iter().map(atomic_market_offer));
    response.sort_by(|a, b| {
        b.available
            .cmp(&a.available)
            .then_with(|| b.created_at.cmp(&a.created_at))
            .then_with(|| b.id.cmp(&a.id))
    });
    Ok(Json(response))
}

fn atomic_market_offer(offer: AtomicSwapRow) -> MarketOffer {
    let state = &offer.state;
    let offered = display_amount(state.offered_amount_sats, state.offered_precision);
    let wanted = display_amount(state.wanted_amount_sats, state.wanted_precision);
    let proposal_json = serde_json::to_string(&offer).unwrap_or_default();
    MarketOffer {
        id: format!("atomic:{}", offer.id),
        source_id: offer.id,
        available: offer.status == "open",
        status: offer.status,
        settlement: "htlc-v1".to_string(),
        demo: false,
        maker_gives: MarketLeg {
            chain: chain_name(&state.offered_chain),
            network: leg_network(&state.offered_chain, &offer.network),
            asset_id: state.offered_asset_id.clone(),
            ticker: state.offered_ticker.clone(),
            name: state.offered_name.clone(),
            precision: state.offered_precision,
            amount_sats: state.offered_amount_sats,
            display_amount: offered.clone(),
        },
        maker_wants: MarketLeg {
            chain: chain_name(&state.wanted_chain),
            network: leg_network(&state.wanted_chain, &offer.network),
            asset_id: state.wanted_asset_id.clone(),
            ticker: state.wanted_ticker.clone(),
            name: state.wanted_name.clone(),
            precision: state.wanted_precision,
            amount_sats: state.wanted_amount_sats,
            display_amount: wanted.clone(),
        },
        price_display: format!("{offered} → {wanted}"),
        note: state.note.clone(),
        created_at: offer.created_at,
        proposal_json,
    }
}

fn liquid_market_offer(offer: OfferRow) -> MarketOffer {
    let offered = display_amount(offer.offered_amount_sats, offer.offered_precision);
    let wanted = display_amount(offer.wanted_amount_sats, offer.wanted_precision);
    MarketOffer {
        id: format!("liquid:{}", offer.id),
        source_id: offer.id,
        available: offer.status == "open",
        status: offer.status,
        settlement: "liquidex-v0".to_string(),
        demo: false,
        maker_gives: MarketLeg {
            chain: "liquid",
            network: offer.network.clone(),
            asset_id: offer.offered_asset_id,
            ticker: offer.offered_ticker,
            name: offer.offered_name,
            precision: offer.offered_precision,
            amount_sats: offer.offered_amount_sats,
            display_amount: offered.clone(),
        },
        maker_wants: MarketLeg {
            chain: "liquid",
            network: offer.network,
            asset_id: offer.wanted_asset_id,
            ticker: offer.wanted_ticker,
            name: offer.wanted_name,
            precision: offer.wanted_precision,
            amount_sats: offer.wanted_amount_sats,
            display_amount: wanted.clone(),
        },
        price_display: format!("{offered} → {wanted}"),
        note: offer.note,
        created_at: offer.created_at,
        proposal_json: offer.proposal_json,
    }
}

fn demo_market_offer(offer: DemoOfferRow) -> MarketOffer {
    let offered = display_amount(offer.offered_amount_sats, offer.offered_precision);
    let wanted = display_amount(offer.wanted_amount_sats, offer.wanted_precision);
    let network = offer.network.clone();
    MarketOffer {
        id: format!("demo:{}", offer.id),
        source_id: offer.id,
        available: offer.status == "open",
        status: offer.status,
        settlement: offer.settlement,
        demo: true,
        maker_gives: MarketLeg {
            chain: chain_name(&offer.offered_chain),
            network: leg_network(&offer.offered_chain, &network),
            asset_id: offer.offered_asset_id,
            ticker: offer.offered_ticker,
            name: offer.offered_name,
            precision: offer.offered_precision,
            amount_sats: offer.offered_amount_sats,
            display_amount: offered.clone(),
        },
        maker_wants: MarketLeg {
            chain: chain_name(&offer.wanted_chain),
            network: leg_network(&offer.wanted_chain, &network),
            asset_id: offer.wanted_asset_id,
            ticker: offer.wanted_ticker,
            name: offer.wanted_name,
            precision: offer.wanted_precision,
            amount_sats: offer.wanted_amount_sats,
            display_amount: wanted.clone(),
        },
        price_display: format!("{offered} → {wanted}"),
        note: offer.note,
        created_at: offer.created_at,
        proposal_json: String::new(),
    }
}

fn chain_name(chain: &str) -> &'static str {
    if chain == "bitcoin" {
        "bitcoin"
    } else {
        "liquid"
    }
}

fn leg_network(chain: &str, liquid_network: &str) -> String {
    if chain == "bitcoin" {
        "bitcoin-testnet".to_string()
    } else {
        liquid_network.to_string()
    }
}

#[derive(Debug, Deserialize)]
struct NetworkQuery {
    #[serde(default = "default_network")]
    network: String,
}

#[derive(Serialize)]
struct AdminStats {
    offers: usize,
    open: usize,
    paused: usize,
    assets: usize,
}

#[derive(Serialize)]
struct AdminState {
    network: String,
    database: String,
    journal_mode: &'static str,
    durability: &'static str,
    stats: AdminStats,
    assets: Vec<AssetRow>,
    offers: Vec<OfferRow>,
    demo_offers: Vec<DemoOfferRow>,
    atomic_swaps: Vec<AtomicSwapRow>,
}

async fn admin_state(
    State(db): State<Arc<Database>>,
    Query(query): Query<NetworkQuery>,
) -> Result<Json<AdminState>, ApiError> {
    validate_network(&query.network).map_err(ApiError::bad_request)?;
    let assets = db.list_assets(&query.network).map_err(ApiError::internal)?;
    let offers = db
        .list_offers(&query.network, true)
        .map_err(ApiError::internal)?;
    let demo_offers = db
        .list_demo_offers(&query.network, true)
        .map_err(ApiError::internal)?;
    let atomic_swaps = db
        .list_atomic_swaps(&query.network, true)
        .map_err(ApiError::internal)?;
    let stats = AdminStats {
        offers: offers.len() + demo_offers.len() + atomic_swaps.len(),
        open: offers.iter().filter(|offer| offer.status == "open").count()
            + demo_offers
                .iter()
                .filter(|offer| offer.status == "open")
                .count()
            + atomic_swaps
                .iter()
                .filter(|offer| offer.status == "open")
                .count(),
        paused: offers
            .iter()
            .filter(|offer| offer.status == "paused")
            .count()
            + demo_offers
                .iter()
                .filter(|offer| offer.status == "paused")
                .count(),
        assets: assets.len(),
    };
    Ok(Json(AdminState {
        network: query.network,
        database: db.path().display().to_string(),
        journal_mode: "WAL",
        durability: "FULL",
        stats,
        assets,
        offers,
        demo_offers,
        atomic_swaps,
    }))
}

async fn create_atomic_swap(
    State(db): State<Arc<Database>>,
    Json(input): Json<AtomicSwapCreate>,
) -> Result<(StatusCode, Json<AtomicSwapRow>), ApiError> {
    let row = db
        .create_atomic_swap(&input)
        .map_err(ApiError::bad_request)?;
    Ok((StatusCode::CREATED, Json(row)))
}

async fn get_atomic_swap(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
) -> Result<Json<AtomicSwapRow>, ApiError> {
    db.get_atomic_swap(id)
        .map_err(ApiError::internal)?
        .map(Json)
        .ok_or_else(|| ApiError {
            status: StatusCode::NOT_FOUND,
            message: format!("Unknown atomic swap: {id}"),
        })
}

async fn transition_atomic_swap(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
    Json(input): Json<AtomicSwapTransition>,
) -> Result<Json<AtomicSwapRow>, ApiError> {
    db.transition_atomic_swap(id, &input)
        .map(Json)
        .map_err(ApiError::bad_request)
}

async fn upsert_asset(
    State(db): State<Arc<Database>>,
    Json(input): Json<AssetInput>,
) -> Result<(StatusCode, Json<AssetRow>), ApiError> {
    let row = db.upsert_asset(&input).map_err(ApiError::bad_request)?;
    Ok((StatusCode::OK, Json(row)))
}

async fn delete_asset(
    State(db): State<Arc<Database>>,
    Path((network, asset_id)): Path<(String, String)>,
) -> Result<StatusCode, ApiError> {
    db.delete_asset(&network, &asset_id)
        .map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct CreateOfferInput {
    network: String,
    proposal_json: String,
    #[serde(default)]
    note: String,
}

async fn create_offer(
    State(db): State<Arc<Database>>,
    Json(input): Json<CreateOfferInput>,
) -> Result<(StatusCode, Json<OfferRow>), ApiError> {
    validate_network(&input.network).map_err(ApiError::bad_request)?;
    let network = network_from_name(&input.network, db.regtest_policy_asset())?;
    let proposal = LiquidexProposal::from_json(input.proposal_json.trim())
        .map_err(|e| ApiError::bad_request(e.to_string()))?;
    let analysis = verify_proposal_on(&proposal, false, &network)
        .map_err(|e| ApiError::bad_request(e.to_string()))?;
    if !analysis.valid {
        let reason = analysis
            .checks
            .iter()
            .find(|check| check.ok == Some(false))
            .and_then(|check| check.note.clone())
            .unwrap_or_else(|| "proposal failed offline verification".to_string());
        return Err(ApiError::bad_request(reason));
    }
    let expected = SwapNetwork::of(&network);
    if analysis.network == SwapNetwork::Mainnet {
        return Err(ApiError::bad_request(
            "Liquid mainnet proposals are not accepted".to_string(),
        ));
    }
    if analysis.network != SwapNetwork::Unknown && analysis.network != expected {
        return Err(ApiError::bad_request(format!(
            "Proposal is {}, but selected book is {}",
            analysis.network.as_str(),
            network.short_name()
        )));
    }
    let row = db
        .create_offer(&NewOffer {
            network: input.network,
            proposal_json: input.proposal_json.trim().to_string(),
            offered_asset_id: analysis.maker_offers.asset_id,
            offered_amount_sats: analysis.maker_offers.amount_sats,
            wanted_asset_id: analysis.maker_wants.asset_id,
            wanted_amount_sats: analysis.maker_wants.amount_sats,
            note: input.note,
        })
        .map_err(ApiError::bad_request)?;
    Ok((StatusCode::CREATED, Json(row)))
}

async fn update_offer(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
    Json(update): Json<OfferUpdate>,
) -> Result<Json<OfferRow>, ApiError> {
    let row = db
        .update_offer(id, &update)
        .map_err(ApiError::bad_request)?;
    Ok(Json(row))
}

async fn delete_offer(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
) -> Result<StatusCode, ApiError> {
    db.delete_offer(id).map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct CreateDemoOfferInput {
    network: String,
    direction: String,
    btc_amount_sats: u64,
    liquid_asset_id: String,
    liquid_amount_sats: u64,
    #[serde(default)]
    note: String,
}

async fn create_demo_offer(
    State(db): State<Arc<Database>>,
    Json(input): Json<CreateDemoOfferInput>,
) -> Result<(StatusCode, Json<DemoOfferRow>), ApiError> {
    validate_network(&input.network).map_err(ApiError::bad_request)?;
    let asset = db
        .get_asset(&input.network, &input.liquid_asset_id)
        .map_err(ApiError::internal)?
        .ok_or_else(|| ApiError::bad_request("Unknown Liquid asset".to_string()))?;
    let btc = (
        "bitcoin".to_string(),
        "btc-testnet".to_string(),
        "BTC".to_string(),
        "Bitcoin".to_string(),
        8,
        input.btc_amount_sats,
    );
    let liquid = (
        "liquid".to_string(),
        asset.asset_id,
        asset.ticker,
        asset.name,
        asset.precision,
        input.liquid_amount_sats,
    );
    let (offered, wanted) = match input.direction.as_str() {
        "btc-to-liquid" => (btc, liquid),
        "liquid-to-btc" => (liquid, btc),
        _ => {
            return Err(ApiError::bad_request(
                "Direction must be btc-to-liquid or liquid-to-btc".to_string(),
            ));
        }
    };
    let row = db
        .create_demo_offer(&NewDemoOffer {
            network: input.network,
            offered_chain: offered.0,
            offered_asset_id: offered.1,
            offered_ticker: offered.2,
            offered_name: offered.3,
            offered_precision: offered.4,
            offered_amount_sats: offered.5,
            wanted_chain: wanted.0,
            wanted_asset_id: wanted.1,
            wanted_ticker: wanted.2,
            wanted_name: wanted.3,
            wanted_precision: wanted.4,
            wanted_amount_sats: wanted.5,
            note: input.note,
        })
        .map_err(ApiError::bad_request)?;
    Ok((StatusCode::CREATED, Json(row)))
}

async fn update_demo_offer(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
    Json(update): Json<OfferUpdate>,
) -> Result<Json<DemoOfferRow>, ApiError> {
    let row = db
        .update_demo_offer(id, &update)
        .map_err(ApiError::bad_request)?;
    Ok(Json(row))
}

async fn delete_demo_offer(
    State(db): State<Arc<Database>>,
    Path(id): Path<u64>,
) -> Result<StatusCode, ApiError> {
    db.delete_demo_offer(id).map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}

fn network_from_name(name: &str, regtest_policy_asset: &str) -> Result<LiquidNetwork, ApiError> {
    match name {
        TESTNET => Ok(LiquidNetwork::testnet()),
        REGTEST => LiquidNetwork::regtest(regtest_policy_asset)
            .map_err(|e| ApiError::bad_request(e.to_string())),
        _ => Err(ApiError::bad_request(format!("Unknown network: {name}"))),
    }
}

fn decimal_units(sats: u64, precision: u8) -> f64 {
    sats as f64 / 10u64.pow(u32::from(precision)) as f64
}

fn display_amount(sats: u64, precision: u8) -> String {
    if precision == 0 {
        return sats.to_string();
    }
    let divisor = 10u64.pow(u32::from(precision));
    let whole = sats / divisor;
    let fraction = sats % divisor;
    format!("{whole}.{fraction:0width$}", width = usize::from(precision))
}

#[derive(Debug)]
struct ApiError {
    status: StatusCode,
    message: String,
}

impl ApiError {
    fn bad_request(message: String) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message,
        }
    }

    fn internal(message: String) -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            message,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({ "error": self.message }))).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amount_format_respects_asset_precision() {
        assert_eq!(display_amount(123_456_789, 8), "1.23456789");
        assert_eq!(display_amount(1234, 2), "12.34");
        assert_eq!(display_amount(12, 0), "12");
    }

    #[test]
    fn book_ratio_is_wanted_units_per_offered_unit() {
        let offer = OfferRow {
            id: 1,
            network: TESTNET.to_string(),
            status: "open".to_string(),
            proposal_json: "{}".to_string(),
            offered_asset_id: "a".repeat(64),
            offered_amount_sats: 100_000_000,
            offered_ticker: "LBTC".to_string(),
            offered_name: "Liquid Bitcoin".to_string(),
            offered_precision: 8,
            wanted_asset_id: "b".repeat(64),
            wanted_amount_sats: 250,
            wanted_ticker: "USDt".to_string(),
            wanted_name: "Test dollars".to_string(),
            wanted_precision: 2,
            note: String::new(),
            created_at: 1,
            updated_at: 1,
        };
        assert_eq!(book_entry(&offer)["ratio"], json!(2.5));
        assert_eq!(
            book_entry(&offer)["input"][0]["amount"],
            json!("1.00000000")
        );
    }
}
