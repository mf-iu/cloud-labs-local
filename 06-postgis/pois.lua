-- osm2pgsql flex style for PlaceFinder: points of interest from OpenStreetMap.
-- Used by load-pois.sh. Data © OpenStreetMap contributors, ODbL 1.0.
-- Only named nodes with an amenity or tourism tag; POIs mapped as areas
-- (ways), e.g. many schools and museums, would need process_way.

local pois = osm2pgsql.define_node_table('pois', {
    { column = 'name', type = 'text', not_null = true },
    { column = 'kind', type = 'text', not_null = true },
    { column = 'geom', type = 'point', projection = 4326, not_null = true },
})

function osm2pgsql.process_node(object)
    local kind = object.tags.amenity or object.tags.tourism
    if kind and object.tags.name then
        pois:insert({
            name = object.tags.name,
            kind = kind,
            geom = object:as_point(),
        })
    end
end
