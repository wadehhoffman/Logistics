# Logistics Route Planner

A route planning dashboard for calculating road distances between mill/supplier locations and Carter Lumber yard locations.

## Files

- **Route-Dashboard.html** — Interactive browser-based dashboard with map, route plotting, and distance calculation
- **Route-Reference.xlsx** — Excel workbook with mill/supplier data, yard data, and a route log
- **Logistics-Routes.xlsx** — Source data: 58 mill and supplier addresses
- **YardList.xlsx** — Source data: 238 yard locations with coordinates

## Route Dashboard

Open `Route-Dashboard.html` in any web browser (requires internet connection).

### How to use

1. Select a mill or supplier from the first dropdown
2. Select a yard from the second dropdown
3. Click **Get Route & Distance**

The dashboard will plot the driving route on the map and display the distance in miles/km along with estimated drive time.

### APIs used (all free, no key required)

- **OpenStreetMap** — Map tiles
- **Nominatim** — Geocoding mill addresses to coordinates
- **OSRM** — Road routing and distance calculation

## Route Reference (Excel)

The Excel workbook contains three sheets:

- **Mills & Suppliers** — All 58 locations with product type, vendor code, and full addresses (filterable)
- **Yards** — All 238 locations with store type, market, manager, and lat/lon coordinates (filterable)
- **Route Log** — Blank template to record route lookups
