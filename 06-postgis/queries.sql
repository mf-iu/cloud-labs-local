-- Example queries for step 06-postgis. Run with: psql "$DATABASE_URL" -f queries.sql
-- No Just-In-Time (JIT) compilation and no parallel workers: simpler plans that
-- are easier to compare.
SET jit = off;
SET max_parallel_workers_per_gather = 0;
\timing on

-- 1. Ten nearest places to Erfurt (lon 11.03, lat 50.98)
SELECT name, country_code, population, round(ST_Distance(geom, p) / 1000) AS km
FROM places, CAST(ST_MakePoint(11.03, 50.98) AS geography) AS p
ORDER BY geom <-> p
LIMIT 10;

-- 2. Exact search on asciiname without and with a B-tree index (name already
--    has the trigram index, which also answers "="). The index is created
--    inside a transaction and rolled back, so the comparison can be repeated.
EXPLAIN ANALYZE
    SELECT name, population FROM places WHERE asciiname = 'Erfurt';

BEGIN;
    CREATE INDEX places_asciiname_idx ON places (asciiname);

    EXPLAIN ANALYZE
        SELECT name, population FROM places WHERE asciiname = 'Erfurt';
ROLLBACK;

-- 3. Places within 50 km, with the query plan (uses places_geom_idx)
EXPLAIN ANALYZE
    SELECT name, population FROM places
    WHERE ST_DWithin(geom, ST_MakePoint(11.03, 50.98)::geography, 50000);

-- 4. Same radius query without index, for comparison
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN ANALYZE
    SELECT name, population FROM places
    WHERE ST_DWithin(geom, ST_MakePoint(11.03, 50.98)::geography, 50000);
RESET enable_indexscan;
RESET enable_bitmapscan;

-- 5. Fuzzy search with trigrams: finds "Würzburg" for "Wuerzburg"
SELECT name, country_code, similarity(name, 'Wuerzburg') AS score FROM places
WHERE name % 'Wuerzburg'
ORDER BY score DESC LIMIT 5;
