-- Geography column and index for the points of interest from pois.lua.
-- osm2pgsql writes geometry(Point, 4326): distances would be in degrees.
-- The generated geography column gives meters and has its own GiST index.
ALTER TABLE pois ADD COLUMN geog geography(Point, 4326)
  GENERATED ALWAYS AS (geom::geography) STORED;
CREATE INDEX pois_geog_idx ON pois USING gist (geog);
ANALYZE pois;
