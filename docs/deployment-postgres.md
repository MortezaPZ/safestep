# PostgreSQL deployment

This is the configuration for a real PostgreSQL server. It does not deploy anything by itself, and it does not invent credentials.

## What you need

1. A PostgreSQL server you can reach (your own VPS, or a hosted instance).
2. Node.js 20 or newer on the app host.
3. A `.env` file that is never committed.

## 1. Create the database

```sql
CREATE ROLE safestep WITH LOGIN PASSWORD 'a-long-random-password';
CREATE DATABASE safestep OWNER safestep;
GRANT ALL PRIVILEGES ON DATABASE safestep TO safestep;
```

If PostgreSQL is on the same machine, `pg_hba.conf` must allow the app host to connect.

## 2. Environment

```bash
cp backend/.env.example backend/.env
```

```
NODE_ENV=production
PORT=4080
DB_DRIVER=pg
DATABASE_URL=postgres://safestep:<password>@<host>:5432/safestep
```

The production secret checks refuse to boot if the secrets are short or left at the example values. Generate them with:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

## 3. Migrate and start

```bash
cd backend
npm install
npm run migrate
npm start
```

The delivery notes use port `4080`.

## What this file does not do

It does not open the database to the public internet, store a password, or claim that a particular host was provisioned.
