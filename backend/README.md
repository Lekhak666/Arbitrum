# IntentRegistry Backend

Indexer + Keeper Bot + REST API for the IntentRegistry smart contract.

## Stack

- **Runtime**: Node.js + TypeScript
- **Chain client**: [viem](https://viem.sh)
- **Database**: PostgreSQL via [Prisma](https://prisma.io)
- **API**: Express

## Architecture

```
┌─────────────────────────────────────────┐
│              src/index.ts               │  ← single entry point
│                                         │
│  ┌──────────┐  ┌────────┐  ┌────────┐  │
│  │ Indexer  │  │ Keeper │  │  API   │  │
│  │          │  │  Bot   │  │        │  │
│  │ getLogs  │  │simulate│  │ REST   │  │
│  │ every 5s │  │ + exec │  │ /api/  │  │
│  │          │  │ every  │  │  v1/   │  │
│  │          │  │  15s   │  │        │  │
│  └────┬─────┘  └───┬────┘  └───┬────┘  │
│       │            │           │       │
│       └────────────┴───────────┘       │
│                    │                   │
│             ┌──────▼──────┐            │
│             │  PostgreSQL │            │
│             └─────────────┘            │
└─────────────────────────────────────────┘
```

## Setup

### 1. Install dependencies

```bash
cd backend
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your RPC URL, contract address, keeper private key, and DB URL
```

### 3. Set up the database

```bash
# Make sure PostgreSQL is running, then:
npx prisma migrate dev --name init
npx prisma generate
```

### 4. Run in development

```bash
npm run dev
```

### 5. Run in production

```bash
npm run build
npm start
```

## API Endpoints

| Method | Path                             | Description                   |
| ------ | -------------------------------- | ----------------------------- |
| `GET`  | `/api/v1/health`                 | Liveness probe                |
| `GET`  | `/api/v1/stats`                  | Aggregate counts              |
| `GET`  | `/api/v1/intents`                | List all intents (filterable) |
| `GET`  | `/api/v1/intents/:intentId`      | Single intent by ID           |
| `GET`  | `/api/v1/users/:address/intents` | All intents for a wallet      |

### Query parameters for `GET /intents`

| Param    | Type    | Description                                                                    |
| -------- | ------- | ------------------------------------------------------------------------------ |
| `user`   | address | Filter by wallet address                                                       |
| `status` | string  | `SUBMITTED` \| `REVEALED` \| `READY` \| `EXECUTED` \| `CANCELLED` \| `EXPIRED` |
| `page`   | number  | Page number (default: 1)                                                       |
| `limit`  | number  | Results per page (default: 20, max: 100)                                       |

## Intent Status Flow

```
SUBMITTED → REVEALED → READY → EXECUTED
                ↓
            CANCELLED
                ↓
             EXPIRED (if past expiry and not executed/cancelled)
```

## Keeper Bot

The keeper bot simulates `executeIntent` before sending to avoid wasting gas when the TWAP condition is not yet met. It only sends a real transaction when the simulation succeeds. A configurable gas price cap (`KEEPER_MAX_GAS_GWEI`) prevents execution during gas spikes.
