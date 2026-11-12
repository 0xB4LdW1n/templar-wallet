mod db;
mod web;

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;

use db::Database;

const DEFAULT_PORT: u16 = 3210;

#[derive(Debug)]
struct Config {
    port: u16,
    db_path: PathBuf,
}

impl Config {
    fn from_args() -> Result<Self, String> {
        let mut port = DEFAULT_PORT;
        let mut db_path = default_db_path();
        let mut args = std::env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--port" => {
                    let raw = args.next().ok_or("--port requires a value")?;
                    port = raw
                        .parse::<u16>()
                        .map_err(|_| format!("Invalid port: {raw}"))?;
                }
                "--db" => {
                    db_path = PathBuf::from(args.next().ok_or("--db requires a path")?);
                }
                "-h" | "--help" => {
                    print_help();
                    std::process::exit(0);
                }
                other => return Err(format!("Unknown argument: {other}")),
            }
        }
        Ok(Self { port, db_path })
    }
}

fn default_db_path() -> PathBuf {
    if let Ok(path) = std::env::var("TEMPLAR_ORDERBOOK_DB") {
        let trimmed = path.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }
    let base = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(".templar-orderbook").join("orderbook.sqlite3")
}

fn print_help() {
    println!(
        "Templar local LiquiDEX order book\n\n\
Usage: templar-orderbook [--port 3210] [--db PATH]\n\n\
The server always binds to 127.0.0.1.\n\
Dashboard: http://127.0.0.1:3210\n\
Database:  ~/.templar-orderbook/orderbook.sqlite3\n"
    );
}

#[tokio::main]
async fn main() {
    let config = Config::from_args().unwrap_or_else(|e| {
        eprintln!("{e}");
        print_help();
        std::process::exit(2);
    });
    let database = Database::open(config.db_path.clone()).unwrap_or_else(|e| {
        eprintln!("Cannot open order-book database: {e}");
        std::process::exit(1);
    });
    let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), config.port);
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .unwrap_or_else(|e| {
            eprintln!("Cannot bind {address}: {e}");
            std::process::exit(1);
        });

    println!("Templar order book: http://{address}");
    println!("SQLite: {}", config.db_path.display());
    println!("Network access: localhost only");

    let app = web::router(Arc::new(database));
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap_or_else(|e| {
            eprintln!("Order-book server failed: {e}");
            std::process::exit(1);
        });
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_local_and_persistent() {
        assert_eq!(DEFAULT_PORT, 3210);
        assert!(default_db_path().ends_with(".templar-orderbook/orderbook.sqlite3"));
    }
}
