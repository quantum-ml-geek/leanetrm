-- Optional point coordinates on the existing versioned location definition.
-- No rewrite of retained coordinates, new table, GIS extension or inferred point.
BEGIN;
ALTER TABLE ref_data.locations
  ADD COLUMN latitude ref_data.exact_number,
  ADD COLUMN longitude ref_data.exact_number,
  ADD CONSTRAINT location_coordinate_pair CHECK (
    (latitude IS NULL AND longitude IS NULL) OR
    (latitude IS NOT NULL AND longitude IS NOT NULL)
  ),
  ADD CONSTRAINT location_latitude_range CHECK (latitude BETWEEN -90 AND 90),
  ADD CONSTRAINT location_longitude_range CHECK (longitude BETWEEN -180 AND 180);
COMMENT ON COLUMN ref_data.locations.latitude IS
  'Optional WGS 84 point latitude in decimal degrees, north positive. Supply together with longitude; NULL is no supplied point, never zero. No rounding on input.';
COMMENT ON COLUMN ref_data.locations.longitude IS
  'Optional WGS 84 point longitude in decimal degrees, east positive. A point does not describe an entire pipeline route, region boundary or hub membership. Coordinate corrections require a new reference revision.';
COMMIT;
