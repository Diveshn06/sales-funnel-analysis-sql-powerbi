--  1. Display all records from the raw sales funnel table.
SELECT * 
FROM sales_funnel;

-- 2. Count the total number of activity records.
SELECT COUNT(*) AS total_count
FROM sales_funnel;

-- 3. Count the total number of unique IRs.
SELECT COUNT(DISTINCT(IR_ID)) AS Total_Unique_ids
FROM sales_funnel;

-- 4. List all Reporting Seniors and the number of IRs working under each.
SELECT Reporting_Senior, COUNT(DISTINCT(name)) AS Total_Irs
FROM sales_funnel
GROUP BY Reporting_Senior;

--  5. Identify records with missing values in any critical column.
SELECT * FROM sales_funnel
WHERE IR_ID IS NULL OR 
activity_date IS NULL OR 
name IS NULL OR 
gender IS NULL OR 
Reporting_Senior IS NULL OR
INFO IS NULL OR 
Invites IS NULL OR 
POT IS NULL OR 
Closings IS NULL ;

--  6. Find IRs who were absent on certain days (not present in daily records).
SELECT a.activity_date, i.IR_ID, i.name, i.Reporting_Senior FROM 
(SELECT DISTINCT(IR_ID),name, Reporting_Senior FROM sales_funnel) AS i
CROSS JOIN
(SELECT DISTINCT(activity_date) FROM sales_funnel) AS a
LEFT JOIN sales_funnel AS sf ON sf.activity_date = a.activity_date AND sf.IR_ID = i.IR_ID
ORDER BY activity_date, IR_ID;

--  7. Identify records where INFO is below the daily target of 5.
SELECT IR_ID, name, Reporting_Senior, COUNT(*) AS below_targets FROM sales_funnel
WHERE INFO < 5
GROUP BY IR_ID, name, Reporting_Senior
ORDER BY below_targets DESC;

--  8. Calculate the percentage of records meeting the INFO target.
SELECT 
(COUNT(CASE WHEN INFO >= 5 THEN 1 END) * 100 / COUNT(*)) AS percentage_meeting_target
FROM sales_funnel ;

-- 9. Detect funnel logic violations where INFO < Invites or Invites < POT or POT < Closings.
SELECT * FROM sales_funnel
WHERE INFO < Invites OR Invites < POT OR POT < Closings;

-- 10. Create a cleaned analytical view from the raw data.
SELECT * ,
CASE WHEN INFO >= 5 THEN 'MATCH_TARGET'
ELSE 'NOT_MATCHED_TARGET'
END AS info_target_status
FROM sales_funnel
WHERE
    ir_id IS NOT NULL
    AND name IS NOT NULL
    AND activity_date IS NOT NULL
    AND INFO IS NOT NULL
    
    AND INFO >= 0
    AND Invites >= 0
    AND POT >= 0
    AND Closings >= 0
    
    AND INFO >= Invites
    AND Invites >= POT
    AND POT >= Closings ;
    

-- 11. Flag each record as Valid, Below Target, or Invalid Funnel.
SELECT *,
CASE
    WHEN INFO < Invites OR Invites < POT OR POT < Closings THEN 'Invalid Funnel'
    WHEN INFO < 5 THEN 'Below Target'
    ELSE 'Valid'
END AS record_status
FROM sales_funnel;


-- 12. Calculate daily totals for INFO, Invites, POT, and Closings.
SELECT
    activity_date,
    SUM(INFO) AS INFO,
    SUM(Invites) AS Invites,
    SUM(POT) AS POT,
    SUM(Closings) AS Closings
FROM sales_funnel
GROUP BY activity_date;


-- 13. Calculate overall funnel conversion rates.
SELECT
    ROUND(SUM(Invites)*100 / SUM(INFO), 2) AS info_to_invites_pct,
    ROUND(SUM(POT)*100 / SUM(Invites), 2) AS invites_to_pot_pct,
    ROUND(SUM(Closings)*100 / SUM(POT), 2) AS pot_to_closings_pct
FROM sales_funnel;


-- 14. Calculate Reporting Senior–wise total INFO and Closings.
SELECT
    Reporting_Senior,
    SUM(INFO) AS total_info,
    SUM(Closings) AS total_closings
FROM sales_funnel
GROUP BY Reporting_Senior;


-- 15. Find Reporting Senior–wise conversion rate.
SELECT Reporting_Senior, ROUND(SUM(Invites)*100 / SUM(INFO), 2) AS info_to_invites_pct, ROUND(SUM(Closings)*100 / SUM(INFO), 2) AS info_to_closings_pct
FROM sales_funnel
GROUP BY Reporting_Senior;


-- 16. Rank IRs by total Closings using window functions.
SELECT IR_ID, name, SUM(Closings) AS total_closings,
RANK() OVER (ORDER BY SUM(Closings) DESC) AS rnk
FROM sales_funnel
GROUP BY IR_ID, name;


-- 17. Identify the top 3 IRs under each Reporting Senior.
WITH x AS (
    SELECT
        Reporting_Senior,
        IR_ID,
        name,
        SUM(Closings) AS total_closings,
        DENSE_RANK() OVER (
            PARTITION BY Reporting_Senior
            ORDER BY SUM(Closings) DESC
        ) AS rnk
    FROM sales_funnel
    GROUP BY Reporting_Senior, IR_ID, name
)
SELECT *
FROM x
WHERE rnk <= 3;



-- 18. Find IRs who consistently fail to meet the INFO target.
SELECT IR_ID, name
FROM sales_funnel
GROUP BY IR_ID, name
HAVING MAX(INFO) < 5;


-- 19. Analyze gender-wise performance and conversion rates.
SELECT gender, SUM(INFO) AS total_info, SUM(Closings) AS total_closings, ROUND(SUM(Closings)*100 / SUM(INFO), 2) AS conversion_pct
FROM sales_funnel
GROUP BY gender;


-- 20. Find days with unusually high or low Closings.
WITH daily AS (
    SELECT activity_date, SUM(Closings) AS closings
    FROM sales_funnel
    GROUP BY activity_date
)
SELECT *,
CASE
    WHEN closings > (SELECT AVG(closings) FROM daily) THEN 'High'
    WHEN closings < (SELECT AVG(closings) FROM daily) THEN 'Low'
    ELSE 'Normal'
END AS closing_level
FROM daily;


-- 21. Calculate cumulative Closings over time.
SELECT activity_date, SUM(Closings) AS daily_closings, 
SUM(SUM(Closings)) OVER (ORDER BY activity_date) AS cumulative_closings
FROM sales_funnel
GROUP BY activity_date;


-- 22. Identify IRs whose performance is above the team average.
SELECT IR_ID, name, SUM(Closings) AS total_closings
FROM sales_funnel
GROUP BY IR_ID, name
HAVING SUM(Closings) >
(SELECT AVG(total)FROM (SELECT SUM(Closings) AS total
        FROM sales_funnel
        GROUP BY IR_ID
    ) x
);


-- 23. Detect Reporting Seniors with below-average team performance.
SELECT Reporting_Senior, SUM(Closings) AS total_closings
FROM sales_funnel
GROUP BY Reporting_Senior
HAVING SUM(Closings) < (SELECT AVG(total) FROM (SELECT SUM(Closings) AS total
        FROM sales_funnel
        GROUP BY Reporting_Senior
    ) x
);


-- 24. Prepare a final KPI-ready dataset for dashboarding
CREATE OR REPLACE VIEW vw_sales_funnel_kpi AS
SELECT activity_date, Reporting_Senior, IR_ID, name, gender, INFO, Invites, POT, Closings,
CASE WHEN INFO >= 5 THEN 1 ELSE 0 END AS target_met
FROM sales_funnel
WHERE INFO >= Invites
  AND Invites >= POT
  AND POT >= Closings;
