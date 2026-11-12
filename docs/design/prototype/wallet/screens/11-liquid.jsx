// 11 — Liquid dashboard: held + issued assets, register, asset ops, recent liquid activity.
(() => {

const LQ_TX = [
  { asset: "LBTC",  id: "9bd1c0fe", note: "swap in",                       amt: "+0.00100000", when: "12 min", in: true },
  { asset: "USDt",  id: "f211d8f8", note: "—",                             amt: "-25.00",      when: "1 hr",   in: false },
  { asset: "DEPIX", id: "a09b2243", note: "issuance · reissuance kept",    amt: "+50.00",      when: "5 days", in: true },
];

const assetPill = (a) =>
  a === "LBTC" ? <Pill tone="lq">LBTC</Pill> :
  a === "USDt" ? <Pill tone="ok">USDt</Pill> :
  <Pill tone="warn">DEPIX</Pill>;

function LiquidScreen({ wallet, go }) {
  const [register, setRegister] = useState(false);
  const [assetId, setAssetId] = useState("");
  const [tracked, setTracked] = useState([]);
  const [syncing, setSyncing] = useState(false);

  const sync = () => {
    if (syncing) return;
    setSyncing(true);
    setTimeout(() => { setSyncing(false); window.toast?.("Liquid synced · height 3,041,143"); }, 1600);
  };

  const opGo = (op) => { window.FLOW.assetOp = op; go("assets"); };
  const sendAsset = (t) => { window.FLOW.sendAsset = t; go("send"); };

  return (
    <React.Fragment>
      <Topbar
        title="Liquid"
        sub="L-BTC + held & issued assets · synced at height 3,041,142"
        right={
          <React.Fragment>
            <Btn onClick={sync}>{syncing ? "syncing…" : "↻ Sync"}</Btn>
            <Btn onClick={() => go("receive")}>↓ Receive</Btn>
            <Btn variant="primary" onClick={() => sendAsset("L-BTC")}>↑ Send</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <div className="g3">
          <Card style={{borderLeft: "3px solid var(--lq)"}}>
            <div className="row" style={{gap: 8}}>
              <LiquidLogo size={26} />
              <strong>L-BTC</strong>
              <span className="spacer" />
              <Pill tone="ok" dot>synced</Pill>
            </div>
            <div className="value-lg mono" style={{marginTop: 12}}>0.00299860</div>
            <div className="dim" style={{fontSize: 12, marginTop: 3}}>4 UTXOs · ≈ $194.91</div>
            <div className="mono dim" style={{fontSize: 11, marginTop: 6}}>144c6541…2dd9c5a8</div>
            <div className="row" style={{marginTop: 12}}>
              <Btn size="sm" onClick={() => sendAsset("L-BTC")}>send</Btn>
              <Btn size="sm" onClick={() => go("receive")}>recv</Btn>
            </div>
          </Card>

          <Card>
            <div className="row" style={{gap: 8}}>
              <AssetGlyph ticker="USDt" size={26} />
              <strong>USDt</strong>
              <span className="spacer" />
              <Pill tone="outline">third-party</Pill>
            </div>
            <div className="value-lg mono" style={{marginTop: 12}}>25.00</div>
            <div className="dim" style={{fontSize: 12, marginTop: 3}}>1 UTXO · ≈ $25.00</div>
            <div className="mono dim" style={{fontSize: 11, marginTop: 6}}>ce091c98…b3742c4</div>
            <div className="row" style={{marginTop: 12}}>
              <Btn size="sm" onClick={() => sendAsset("USDt")}>send</Btn>
              <Btn size="sm" onClick={() => go("receive")}>recv</Btn>
            </div>
          </Card>

          <Card tone="warn" className="fx-beam">
            <div className="row" style={{gap: 8}}>
              <AssetGlyph ticker="DEPIX" size={26} />
              <strong>DEPIX</strong>
              <span className="spacer" />
              <Pill tone="warn">your asset</Pill>
            </div>
            <div className="value-lg mono" style={{marginTop: 12}}>50.00</div>
            <div className="dim" style={{fontSize: 12, marginTop: 3}}>1 UTXO · —</div>
            <div className="mono dim" style={{fontSize: 11, marginTop: 6}}>a09b2243…b9c1f10</div>
            <div style={{marginTop: 8}}><Pill tone="ok" dot>reissuance token held</Pill></div>
            <div className="row" style={{marginTop: 12}}>
              <Btn size="sm" onClick={() => sendAsset("DEPIX")}>send</Btn>
              <Btn size="sm" onClick={() => go("receive")}>recv</Btn>
              <Btn size="sm" variant="ghost" onClick={() => opGo("reissue")}>manage →</Btn>
            </div>
          </Card>
        </div>

        {tracked.map(t => (
          <Card key={t} tight style={{marginTop: 14}}>
            <div className="between">
              <span className="row" style={{gap: 8}}>
                <AssetGlyph ticker="?" size={22} />
                <strong>Registered asset</strong>
                <span className="mono dim" style={{fontSize: 12}}>{t.slice(0, 8)}…{t.slice(-6)}</span>
              </span>
              <Pill tone="outline">0 balance · watching</Pill>
            </div>
          </Card>
        ))}

        <div className="picker-card add" style={{marginTop: 14, minHeight: 130, cursor: "pointer"}} onClick={() => setRegister(true)}>
          <div style={{textAlign: "center"}}>
            <div style={{fontSize: 20, marginBottom: 4}}>+</div>
            <div style={{fontWeight: 500, color: "var(--ink-2)"}}>Register asset</div>
            <div className="dim" style={{fontSize: 12, marginTop: 3}}>paste an asset ID</div>
          </div>
        </div>

        <SectionH>Asset operations</SectionH>
        <div className="g4">
          <Card tight style={{cursor: "pointer"}} onClick={() => opGo("issue")}>
            <strong>+ Issue new</strong>
            <p className="sub" style={{margin: "4px 0 0", fontSize: 12.5}}>Mint your own Liquid token.</p>
          </Card>
          <Card tight style={{cursor: "pointer"}} onClick={() => opGo("reissue")}>
            <strong>↑↑ Reissue</strong>
            <p className="sub" style={{margin: "4px 0 0", fontSize: 12.5}}>Mint more of an existing asset.</p>
          </Card>
          <Card tight style={{cursor: "pointer"}} onClick={() => opGo("burn")}>
            <strong>△ Burn</strong>
            <p className="sub" style={{margin: "4px 0 0", fontSize: 12.5}}>Permanently remove supply.</p>
          </Card>
          <Card tight style={{cursor: "pointer"}} onClick={() => {
            download("asset-registry.json", JSON.stringify({
              asset_id: "a09b2243…b9c1f10", contract: { name: "DePix", ticker: "DEPIX", precision: 8, entity: { domain: "depix.local" }, version: 0 },
            }, null, 2));
            window.toast?.("Registry JSON exported");
          }}>
            <strong>⇩ Export registry</strong>
            <p className="sub" style={{margin: "4px 0 0", fontSize: 12.5}}>For asset-registry submission.</p>
          </Card>
        </div>

        <SectionH right={<Btn variant="ghost" size="sm" onClick={() => go("history")}>all liquid tx →</Btn>}>
          Recent Liquid activity
        </SectionH>
        <Card tabular>
          <table className="table">
            <tbody>
              {LQ_TX.map(tx => (
                <tr key={tx.id} onClick={() => go("history")} style={{cursor: "pointer"}}>
                  <td style={{width: 80}}>{assetPill(tx.asset)}</td>
                  <td className="mono">{tx.id}</td>
                  <td className="dim">{tx.note}</td>
                  <td className={`num ${tx.in ? "amount-in" : ""}`}>{tx.amt}</td>
                  <td className="num dim" style={{width: 90}}>{tx.when}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      </div>

      {register && (
        <Modal title="Register an asset" onClose={() => setRegister(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setRegister(false)}>cancel</Btn>
              <Btn variant="primary"
                disabled={assetId.trim().length < 16}
                style={assetId.trim().length < 16 ? {opacity: 0.5, pointerEvents: "none"} : null}
                onClick={() => { setTracked(t => [...t, assetId.trim()]); setAssetId(""); setRegister(false); window.toast?.("Asset registered — watching for UTXOs"); }}>
                Register →
              </Btn>
            </React.Fragment>
          }>
          <Field label="Asset ID" hint="64-hex asset tag. Templar will look up registry metadata and start tracking UTXOs.">
            <input className="input mono" placeholder="144c6541…" value={assetId} onChange={e => setAssetId(e.target.value)} />
          </Field>
        </Modal>
      )}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).liquid = LiquidScreen;
})();
