-- Run once after PostGIS is available
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(80) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    annotation_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sightings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    photo_url VARCHAR(1024) NOT NULL,
    thumbnail_url VARCHAR(1024),
    location GEOMETRY(POINT, 4326) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    notes TEXT,
    ai_species_suggestion VARCHAR(255),
    ai_confidence DOUBLE PRECISION,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS sightings_location_idx ON sightings USING GIST (location);
CREATE INDEX IF NOT EXISTS sightings_user_idx ON sightings (user_id);

CREATE TABLE IF NOT EXISTS annotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sighting_id UUID NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    species VARCHAR(255) NOT NULL,
    confidence DOUBLE PRECISION DEFAULT 1.0,
    behavior VARCHAR(255),
    age_plumage VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS annotations_sighting_idx ON annotations (sighting_id);

CREATE TABLE IF NOT EXISTS model_versions (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) UNIQUE NOT NULL,
    s3_key VARCHAR(1024) NOT NULL,
    num_classes INTEGER NOT NULL,
    accuracy DOUBLE PRECISION,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);
