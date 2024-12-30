-- BUSINESS REQUEST #1 Start
SELECT 
city_name,
count(trip_id) as "total_trips",
ROUND(sum(trips_db.fact_trips.fare_amount)/sum(trips_db.fact_trips.distance_travelled_km),2) avg_fare_per_km,
ROUND(sum(trips_db.fact_trips.fare_amount)/count(trip_id),2) avg_fare_per_trip,
ROUND((COUNT(trip_id) * 100.0 / (SELECT COUNT(*) FROM trips_db.fact_trips)), 2) AS "%_contribution_to_total_trips"
FROM trips_db.fact_trips
INNER JOIN trips_db.dim_city
ON trips_db.fact_trips.city_id = trips_db.dim_city.city_id
GROUP BY 1
ORDER BY 2 DESC;
-- BUSINESS REQUEST #1 End

-- BUSINESS REQUEST #2 Start
SELECT 
	dc.city_name,
    MONTHNAME(mt.month) AS month_name,
    COALESCE(ft.actual_trips, 0) AS actual_trips,
    mt.total_target_trips,
    CASE
    WHEN ft.actual_trips <= mt.total_target_trips THEN "Below Target"
    WHEN ft.actual_trips > mt.total_target_trips THEN "Above Target"
    END AS "performance_status",
    ROUND(((COALESCE(ft.actual_trips, 0) - mt.total_target_trips)/ mt.total_target_trips)*100.0, 2) AS "%_difference"
FROM 
    targets_db.monthly_target_trips AS mt
LEFT JOIN (
-- Join over aggregated fact_trips table, left join in case a particular month a city did not have any actual trips
    SELECT 
        DATE_FORMAT(date, '%Y-%m-01') AS month,
        city_id,
        COUNT(*) AS actual_trips
    FROM 
        trips_db.fact_trips
    GROUP BY 
        city_id, month
) AS ft
ON mt.city_id = ft.city_id AND mt.month = ft.month
LEFT JOIN trips_db.dim_city AS dc
ON mt.city_id = dc.city_id
ORDER BY 
    dc.city_name,mt.month;
-- BUSINESS REQUEST #2 End

-- BUSINESS REQUEST #3 Start
SELECT 
    city_name,
    ROUND(SUM(CASE WHEN trip_count = "2-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "2-Trips",
    ROUND(SUM(CASE WHEN trip_count = "3-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "3-Trips",
    ROUND(SUM(CASE WHEN trip_count = "4-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "4-Trips",
    ROUND(SUM(CASE WHEN trip_count = "5-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "5-Trips",
    ROUND(SUM(CASE WHEN trip_count = "6-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "6-Trips",
    ROUND(SUM(CASE WHEN trip_count = "7-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "7-Trips",
    ROUND(SUM(CASE WHEN trip_count = "8-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "8-Trips",
    ROUND(SUM(CASE WHEN trip_count = "9-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "9-Trips",
    ROUND(SUM(CASE WHEN trip_count = "10-Trips" THEN repeat_passenger_count ELSE 0 END) * 100.0 /
        SUM(repeat_passenger_count), 2) AS "10-Trips"
FROM trips_db.dim_repeat_trip_distribution rt
LEFT JOIN trips_db.dim_city dc
ON  dc.city_id = rt.city_id
GROUP BY city_name;
-- BUSINESS REQUEST #3 End


-- BUSINESS REQUEST #4 Start
WITH ranked_cities AS (
    SELECT 
        dc.city_name,
        SUM(fp.new_passengers) AS total_new_passengers,
        ROW_NUMBER() OVER (ORDER BY SUM(fp.new_passengers) DESC) AS rank_desc,
        ROW_NUMBER() OVER (ORDER BY SUM(fp.new_passengers)) AS rank_asc
    FROM trips_db.fact_passenger_summary fp
    LEFT JOIN trips_db.dim_city dc
    ON dc.city_id = fp.city_id
    GROUP BY dc.city_name
),
top_3 AS (
    SELECT 
        city_name,
        total_new_passengers,
        "Top 3" AS city_category
    FROM ranked_cities
    WHERE rank_desc <= 3
),
bottom_3 AS (
    SELECT 
        city_name,
        total_new_passengers,
        "Bottom 3" AS city_category
    FROM ranked_cities
    WHERE rank_asc <= 3
)
SELECT * FROM top_3
UNION ALL
SELECT * FROM bottom_3;
-- BUSINESS REQUEST #4 End

-- BUSINESS REQUEST #5 Start
WITH monthly_revenue AS (
    -- Aggregate monthly revenue for each city
    SELECT 
        dc.city_name,
        dt.month_name,
        ROUND(SUM(ft.fare_amount), 2) AS total_revenue
    FROM trips_db.fact_trips ft
    LEFT JOIN trips_db.dim_city dc
        ON ft.city_id = dc.city_id
    LEFT JOIN trips_db.dim_date dt
        ON ft.date = dt.date
    GROUP BY dc.city_name, dt.month_name
),
city_rankings AS (
    -- Rank months by revenue within each city
    SELECT 
        city_name,
        month_name,
        total_revenue,
        ROW_NUMBER() OVER (PARTITION BY city_name ORDER BY total_revenue DESC) AS rank_desc,
        SUM(total_revenue) OVER (PARTITION BY city_name) AS city_total_revenue
    FROM monthly_revenue
)
-- Extract the top-ranked month for each city and calculate the percentage contribution
SELECT 
    city_name AS "city_name",
    month_name AS "highest_revenue_month",
    total_revenue AS "revenue",
    ROUND((total_revenue / city_total_revenue) * 100, 2) AS "percentage_contribution (%)"
FROM city_rankings
WHERE rank_desc = 1
ORDER BY city_name;
-- BUSINESS REQUEST #5 End

-- BUSINESS REQUEST #6 Start
WITH monthly_rate as
(
SELECT 
    fps.month,
    dc.city_name,
    fps.repeat_passengers,
    fps.total_passengers,
    ROUND((fps.repeat_passengers / NULLIF(fps.total_passengers, 0)) * 100, 2) AS monthly_repeat_passenger_rate
FROM trips_db.fact_passenger_summary fps
JOIN trips_db.dim_city dc
    ON fps.city_id = dc.city_id
),
city_rate as (
SELECT 
    dc.city_name,
    SUM(fps.repeat_passengers) AS total_repeat_passengers,
    SUM(fps.total_passengers) AS total_passengers,
    ROUND((SUM(fps.repeat_passengers) / NULLIF(SUM(fps.total_passengers), 0)) * 100, 2) AS city_repeat_passenger_rate
FROM
    trips_db.fact_passenger_summary fps
        JOIN
    trips_db.dim_city dc ON fps.city_id = dc.city_id
GROUP BY 1
)
SELECT 
mr.city_name,
DATE_FORMAT(mr.month, '%M') AS month,
mr.total_passengers,
mr.repeat_passengers,
mr.monthly_repeat_passenger_rate,
cr.city_repeat_passenger_rate
FROM monthly_rate mr
JOIN city_rate cr
ON cr.city_name = mr.city_name
ORDER BY mr.city_name, mr.month;
-- BUSINESS REQUEST #6 End
