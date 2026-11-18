# AgentWall — Binance Agent ID Hackathon Project

**AgentWall** is an on-chain guestbook & daily check-in wall on BNB Chain,
exclusively for Agent ID holders: the contract checks `balanceOf(msg.sender) > 0`
on the official Agent ID contract (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`)
before accepting any post or check-in. Everyone can read; only holders can write.

**Status (2026-11-18): DEPLOYED on BSC mainnet; source verified on Sourcify
(exact match) AND natively on BscScan — both completed 2026-11-18.**
Deployed through the canonical CREATE2 factory
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`), because the owner's Agentic
Wallet (`baw contract-call`) needs a `to` address and cannot send a bare
creation transaction. The contract landed exactly at the predicted CREATE2
address (salt 0).
Submission deadline: **2026-12-09 08:00 UTC**.

## Deployment record (BSC mainnet, chain 56)

| Item | Value |
|---|---|
| Contract address | **`0x96543907190f979f095F64cac9Fd7bF2f384bb26`** |
| Deploy transaction | `0x344be2ed8936e86202f50f2a0dc21b9085258f0d46c56f44ee057969cab1f412` (status: success) |
| Block | 134,311,554 |
| Gas used | 1,019,103 |
| Effective gas price | ≈0.0958 gwei |
| Actual deploy fee | ≈0.0000976 BNB |
| `owner()` (confirmed on-chain) | `0x94D7FDcB7F910C1d389BCE3a4a83C089df6c696D` |
| `agentID()` | `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` |

## Verification record

- **Sourcify: ✅ exact match (full match)** — runtime and creation both
  `exact_match`, verified 2026-11-18 12:21:56 UTC. The verified source served
  by Sourcify is byte-identical to `contracts/AgentWall.sol`.
  - Record: https://sourcify.dev/server/v2/contract/56/0x96543907190f979f095F64cac9Fd7bF2f384bb26
  - Lookup UI: https://sourcify.dev/#/lookup/0x96543907190f979f095F64cac9Fd7bF2f384bb26
- **BscScan (native): ✅ verified 2026-11-18** — completed by the owner from
  his own phone via the BscScan web form ("Successfully generated matching
  Bytecode and ABI"). The programmatic path needs an account-bound API key
  (forge: `ETHERSCAN_API_KEY must be set`) and the agent browser was
  auto-rejected by the form's Cloudflare Turnstile, so the owner's device
  was the working route. Full record: `results/VERIFICATION.md`.
  - Contract page: https://bscscan.com/address/0x96543907190f979f095F64cac9Fd7bF2f384bb26#code

## What's in here

| Path | What it is |
|---|---|
| `contracts/AgentWall.sol` | The product contract (solc 0.8.24, self-contained, no imports). Non-payable by design; owner powers minimal & documented in the header. Constructor takes `(agentID_, initialOwner_)` — the owner is an explicit argument because deployment goes through the CREATE2 factory (inside the constructor, `msg.sender` would be the factory). |
| `contracts/MockAgentID.sol` | Test-only mock of the Agent ID registry. **Never deploy.** |
| `test/AgentWall.t.sol` | Foundry test suite — **29/29 passing** (incl. deployer≠owner and CREATE2 factory tests). |
| `results/forge-test-output.txt` | Raw test output. |
| `results/TEST-RESULTS.md` | Test summary + gas measurements + CREATE2 address cross-check. |
| `results/factory-calldata.txt` | Precomputed factory payload for mainnet deployment: salt (32 zero bytes) ‖ init code (creation bytecode + ABI-encoded Agent ID + initial owner addresses). Its sha256 is in `results/factory-calldata.sha256`. (The old bare-creation `deploy-calldata.txt` is superseded and removed.) |
| `frontend/index.html` | Complete single-file dApp (ethers.js via CDN). Reads via public BSC RPC; writes via the visitor's injected wallet. Has a marked `CONFIG` block with the `CONTRACT_ADDRESS` placeholder. |
| `DEPLOY-PLAN.md` | Exact deploy steps + live gas/balance math. |
| `SUBMISSION.md` | Submission-form text, ready to paste (2 placeholders). |
| `foundry.toml` | Build config: solc 0.8.24, optimizer 200 runs. |

## Test results (summary)

29 passed / 0 failed — holder gating, text limits (0 / 280 / 281 bytes), 1-hour
post cooldown (incl. per-address isolation), check-in streaks (increment,
same-day revert, missed-day reset), pagination, owner-power scope (pause blocks
writes not reads; non-owner reverts; ownership transfer), zero-address guards
(incl. both constructor args), asset safety (plain BNB transfers to the contract
revert; it can hold nothing), constructor ownership semantics (a third party can
deploy while `initialOwner_` becomes owner), and CREATE2 factory deployment
(deploys to the formula-predicted address with the correct owner).

Gas: factory-deploy execution 1,032,818 · full factory-route deploy estimate
**1,127,638 gas** (planning figure 1,130,000) ·
`postMessage` ≈ 151,759 · `checkIn` ≈ 100,850 (execution gas).

## Money math (measured live 2026-11-18 12:09–12:14 UTC)

- BSC gas price: **0.05 gwei** · Wallet `0x94D7…696D` balance: **0.0006246 BNB**
- Deploy at current price: **≈0.0000565 BNB → covered ~11×, NO top-up needed**
  (break-even gas price ≈0.553 gwei; shortfall table in `DEPLOY-PLAN.md`).

## What remains

1. ~~**Deploy** via the owner's Agentic Wallet (`baw`)~~ — **DONE**
   2026-11-18 (see Deployment record above).
2. **Verify** the contract source — **Sourcify DONE** (exact match).
   **BscScan native verification still pending**: needs a free BscScan
   account API key, then one `forge verify-contract` command (see
   `DEPLOY-PLAN.md` step 6).
3. **Wire & host** the frontend: set `CONTRACT_ADDRESS` in `frontend/index.html`
   to `0x96543907190f979f095F64cac9Fd7bF2f384bb26`, host the single file
   (hosting choice pending), note the URL.
4. **Submit** using `SUBMISSION.md` before **2026-12-09 08:00 UTC**.
5. **Drive ≥30 Agent ID holder interactions** (distinct addresses posting /
   checking in) during the submission window — Innovation Award eligibility —
   via outreach to Agent ID holder communities; countable on-chain via events.
6. *(Optional, parallel)* Community Promotion campaign: an original X post about
   AgentWall with #BinanceWalletHackathon + #AgenticWallet, submitted via the
   official survey (20 × 100 USDC pool).

## Rebuild / retest

```bash
export PATH="$PATH:$HOME/.foundry/bin"   # Foundry installed user-locally (~/.foundry)
cd ~/workspace/agentid-hackathon
forge build && forge test -vv
```
