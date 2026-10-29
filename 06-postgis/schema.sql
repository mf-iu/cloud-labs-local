-- Table for GeoNames places (same columns as the GeoNames dump files)
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

DROP TABLE IF EXISTS places;

CREATE TABLE places (
    geonameid         integer PRIMARY KEY,
    name              text NOT NULL,
    asciiname         text,
    alternatenames    text,
    latitude          double precision NOT NULL,
    longitude         double precision NOT NULL,
    feature_class     char(1),
    feature_code      text,
    country_code      char(2),
    cc2               text,
    admin1_code       text,
    admin2_code       text,
    admin3_code       text,
    admin4_code       text,
    population        bigint,
    elevation         integer,
    dem               integer,
    timezone          text,
    modification_date date
);
