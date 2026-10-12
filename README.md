# Early Storehouse — Phytoacoustics

On-chain provenance for phytoacoustic trial data.

This repository holds the Phase 0 "build proof" infrastructure for Early
Storehouse: an ERC-1155 smart contract that timestamps each published
phytoacoustic trial dataset on-chain. Every dataset is minted as a unique
token (`id >= 1`, `supply == 1`) together with an immutable record of its
content hash and experimental parameters — giving a tamper-evident trail
for null results as well as positive ones.

Target chain: **Optimism** (L2) · Owner: a **Gnosis Safe** multisig.

> **Status:** contract complete and verified locally — `forge build` clean
> (solc 0.8.24, `cancun`, no lint warnings), `forge fmt --check` clean, and
> **21/21 tests passing**. Runtime bytecode is **8,570 B** against the
> 24,576 B EIP-170 limit. Not yet deployed.

## Contract

`src/PhytoacousticDataset.sol` — an ERC-1155 registry built on OpenZeppelin
v5 (`ERC1155URIStorage`, `ERC1155Burnable`, `Ownable`).

| Function | Access | Purpose |
| --- | --- | --- |
| `publish(researcher, uri, contentHash, crop, frequencyHz, treatment)` | owner | Mint one token for a new dataset and write its provenance record; returns the `tokenId`. |
| `record(tokenId)` | anyone | Read the stored `DatasetRecord` (`contentHash`, `crop`, `treatment`, `frequencyHz`, `timestamp`). |
| `setDatasetURI(tokenId, uri)` | owner | Re-pin the metadata URI (e.g. after re-uploading to Arweave). Content hash is immutable. |
| `setSoulbound(tokenId, locked)` | owner | Freeze an individual dataset so it can no longer be transferred. |
| `datasetCount()` | anyone | Number of datasets published so far (also the latest token id). |
| `uri(tokenId)` | anyone | ERC-1155 metadata URI (typically an `ar://` Arweave pointer). |

### Token model — transferable, with a soulbound toggle

Tokens are **transferable by default**, which keeps them interoperable with
wallets, marketplaces and DeSci tooling, and leaves room for IP-NFT style
mechanics later. Because the provenance record lives in a contract mapping,
it is **immutable regardless of whether a token moves** — so locking
transfers is never required to preserve the proof.

When a dataset should be a permanent historical artefact, the owner can flip
`setSoulbound(id, true)` to freeze that single token. Locked tokens can still
be burned. This "hybrid" approach avoids the dead-end of a fully soulbound
contract while keeping the option to enshrine individual records.

## Repository layout

```
.
├── foundry.toml                 # solc 0.8.24, Optimism RPC + etherscan config
├── remappings.txt               # OpenZeppelin + forge-std import paths
├── src/
│   └── PhytoacousticDataset.sol # the registry contract
├── script/
│   └── Deploy.s.sol             # deployment script (sets owner = Gnosis Safe)
├── test/
│   └── PhytoacousticDataset.t.sol
├── .github/workflows/test.yml   # CI: forge fmt --check, build, test
├── .gitattributes               # LF normalisation across platforms
├── .env.example                 # copy to .env and fill in
└── README.md
```

## Prerequisites

Install [Foundry](https://book.getfoundry.sh/getting-started/installation):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Setup

Dependencies are **git submodules**, so clone recursively:

```bash
git clone --recursive https://github.com/Early-storehouse/early-storehouse-phytoacoustics.git
cd early-storehouse-phytoacoustics

# Already cloned without --recursive? Fetch the dependencies with:
git submodule update --init --recursive
```

Pinned dependencies:

| Dependency | Version | Path |
| --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | `v5.1.0` | `lib/openzeppelin-contracts` |
| [forge-std](https://github.com/foundry-rs/forge-std) | `v1.9.4` | `lib/forge-std` |

## Build & test
-- https://book.getfoundry.sh/forge/building-and-testing
```bash
forge build
forge test -vvv
```

Expected result: `21 tests passed, 0 failed`. The compiled runtime bytecode is
**8,570 B**, leaving a comfortable margin under the 24,576 B EIP-170 limit.
CI (`.github/workflows/test.yml`) runs `forge fmt --check`, `forge build --sizes`
and `forge test` on every push and pull request.

## Deploy to Optimism

```bash
cp .env.example .env        # then fill in PRIVATE_KEY and OWNER (Gnosis Safe)

# Dry run (no broadcast):
forge script script/Deploy.s.sol:DeployPhytoacousticDataset --rpc-url optimism

# Broadcast + verify:
forge script script/Deploy.s.sol:DeployPhytoacousticDataset \
  --rpc-url optimism --broadcast --verify
```

The contract owner is set to the `OWNER` address at construction. Deploy with
`OWNER` pointed at the Early Storehouse Gnosis Safe so that publishing is a
multisig action from day one. To rehearse cheaply, use `--rpc-url
optimism_sepolia` first.

## Publishing your first dataset

```bash
# 1. Upload the dataset + metadata JSON to Arweave and note the URI
#    (e.g. ar://<tx-id>) and the content hash.

# 2. Publish via cast, as the owner / Gnosis Safe:
cast send $DATASET_ADDRESS \
  "publish(address,string,string,string,uint32,string)" \
  $RESEARCHER "ar://<tx-id>" "<content-hash>" "radish" 250 "acoustic" \
  --rpc-url optimism --private-key $PRIVATE_KEY
```

## Design notes

- **Provenance lives in a mapping**, not derived from token ownership, so it
  survives transfers and burns.
- **One token per dataset** (`supply == 1`) keeps "who holds this record"
  unambiguous.
- **Owner = Gnosis Safe**, so the publish / administrative keys are never a
  single hot wallet.
- **Arweave for payload, Optimism for proof** — the chain only stores the
  content hash and parameters, keeping gas costs trivial.

## License

Apache-2.0 — see [LICENSE](./LICENSE).

