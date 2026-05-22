/*
================================================================================
ESPN Men's College Basketball JSONL -> Clean Snowflake Views
================================================================================
Raw files / raw tables expected:
  espn_team.jsonl      -> ESPN_DB.RAW.RAW_ESPN_TEAM
  espn_record.jsonl    -> ESPN_DB.RAW.RAW_ESPN_RECORD
  espn_roster.jsonl    -> ESPN_DB.RAW.RAW_ESPN_ROSTER
  espn_schedule.jsonl  -> ESPN_DB.RAW.RAW_ESPN_SCHEDULE
  espn_athlete.jsonl   -> ESPN_DB.RAW.RAW_ESPN_ATHLETE
  espn_group.jsonl     -> ESPN_DB.RAW.RAW_ESPN_GROUP
================================================================================
*/

/*===============================================================================
0. DATABASE / SCHEMA SETUP

Purpose:
  Create the Snowflake database and schemas used throughout the project.

Why:
  The project separates raw API-loaded JSON from cleaned analysis views:
    - RAW stores the original JSONL-loaded data.
    - ANALYTICS stores cleaned views used for EDA and modeling.

Notes:
  IF NOT EXISTS prevents Snowflake from overwriting existing objects.
  These statements are safe to rerun.
===============================================================================*/

-- Create the project database if it does not already exist.
-- This keeps all NCAA basketball raw and cleaned objects in one database.
CREATE DATABASE IF NOT EXISTS ESPN_DB;

-- Create a RAW schema to store the unmodified JSONL-loaded tables.
-- Keeping raw data separate makes it easier to audit or rebuild cleaned views later.
CREATE SCHEMA IF NOT EXISTS ESPN_DB.RAW;

-- Create an ANALYTICS schema to store cleaned views and analysis-ready tables.
-- This keeps transformation logic separate from the original raw data.
CREATE SCHEMA IF NOT EXISTS ESPN_DB.ANALYTICS;

-- Set the active database so later unqualified references point to ESPN_DB.
USE DATABASE ESPN_DB;

-- Set the active schema to ANALYTICS because most of the remaining script creates views used for analysis.
USE SCHEMA ANALYTICS;

/*===============================================================================
1. RAW TABLE SETUP

Purpose:
  Create one raw table for each JSONL file loaded from the ESPN API pull.

How:
  Each table has a single SRC column of type VARIANT. In Snowflake, VARIANT is
  used to store semi-structured data like JSON. Each row in these tables
  represents one JSONL line from the corresponding file.

Why:
  Keeping the raw API responses in one flexible SRC column preserves the original
  ESPN JSON structure. This makes the raw layer easy to reload, audit, and reuse
  if we later decide to extract different fields for analysis.

Notes:
  CREATE TABLE IF NOT EXISTS is used so these statements are safe to rerun.
  They will not overwrite or delete data if the tables already exist.
===============================================================================*/

-- Stores one raw JSON object per team from espn_team.jsonl.
-- This table is the base source for team identity fields such as team name,
-- abbreviation, mascot, location, group reference, and record reference.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_TEAM (
    SRC VARIANT
);

-- Stores one raw JSON object per team record from espn_record.jsonl.
-- This table is used to extract season-level performance stats such as wins,
-- losses, win percentage, points per game, and point differential.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_RECORD (
    SRC VARIANT
);

-- Stores one raw JSON object per team roster from espn_roster.jsonl.
-- This table primarily contains athlete reference links and can be used for
-- validation against the fully pulled athlete profile data.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_ROSTER (
    SRC VARIANT
);

-- Stores one raw JSON object per team schedule and season type from espn_schedule.jsonl.
-- This table is used to extract game-level information such as game ID, date,
-- opponent, score, home/away flag, attendance, and season type.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_SCHEDULE (
    SRC VARIANT
);

-- Stores one raw JSON object per athlete profile from espn_athlete.jsonl.
-- This table is used to create player-level analysis fields such as position,
-- height, weight, class year, hometown, and active status.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_ATHLETE (
    SRC VARIANT
);

-- Stores one raw JSON object per ESPN group from espn_group.jsonl.
-- Groups are used to map teams to conferences and parent divisions, including
-- identifying NCAA Division I teams.
CREATE TABLE IF NOT EXISTS ESPN_DB.RAW.RAW_ESPN_GROUP (
    SRC VARIANT
);

/*===============================================================================
2. QUICK RAW LOAD CHECKS

Purpose:
  Confirm that each JSONL file was successfully loaded into its corresponding
  raw Snowflake table before creating cleaned analysis views.

How:
  The first query uses UNION ALL to stack row counts from all six raw tables into
  one compact output. This makes it easy to compare whether the expected raw
  datasets loaded successfully.

Why:
  These checks catch loading issues early, such as an empty table, missing file,
  or failed upload. The cleaned views depend on these raw tables, so it is useful
  to validate the raw layer before continuing.

Notes:
  UNION ALL keeps each row count result and does not try to remove duplicates.
  These queries only inspect the data; they do not modify any tables.
===============================================================================*/

-- Count rows in each raw table to verify that all six JSONL files loaded.
-- Each SELECT returns one table name and its row count; UNION ALL stacks those
-- results into a single summary table.
SELECT 'RAW_ESPN_TEAM' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_TEAM
UNION ALL
SELECT 'RAW_ESPN_RECORD' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_RECORD
UNION ALL
SELECT 'RAW_ESPN_ROSTER' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_ROSTER
UNION ALL
SELECT 'RAW_ESPN_SCHEDULE' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_SCHEDULE
UNION ALL
SELECT 'RAW_ESPN_ATHLETE' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_ATHLETE
UNION ALL
SELECT 'RAW_ESPN_GROUP' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM ESPN_DB.RAW.RAW_ESPN_GROUP;

-- Preview a few raw team records to confirm the JSON structure loaded correctly.
-- This is useful for checking that each row is stored in the SRC VARIANT column
-- and that metadata fields like team_id, season, and raw_json are available.
SELECT SRC
FROM ESPN_DB.RAW.RAW_ESPN_TEAM
LIMIT 5;

/*===============================================================================
3. CLEAN BASE VIEWS

Purpose:
  Convert the raw SRC JSON objects into readable, analysis-friendly views.

How:
  These views pull selected fields out of the SRC VARIANT column using Snowflake
  JSON path syntax. Fields directly under SRC are metadata created during the
  API pull, while fields under SRC:raw_json come from the original ESPN API
  response.

Why:
  The raw tables preserve the original JSON structure, but they are difficult to
  analyze directly. These views create cleaner column names and organize the
  core team, conference, and division fields needed for downstream analysis.

Notes:
  These are views, not tables. They do not duplicate or modify the raw data.
  If the raw data changes, these views automatically reflect the updated source.
===============================================================================*/

/*-------------------------------------------------------------------------------
3A. Teams

Purpose:
  Create a readable team-level view from the raw ESPN team file.

How:
  Pulls team identifiers, names, abbreviations, mascot, location, and ESPN
  reference links from the SRC JSON column.

Why:
  This view becomes the base team dimension used to join team records, players,
  games, conferences, and divisions.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_TEAMS_CLEAN AS
SELECT
    SRC:team_id::STRING AS TEAM_ID,
    SRC:season::NUMBER AS SEASON,
    SRC:team_ref::STRING AS TEAM_REF,
    SRC:raw_json:id::STRING AS ESPN_TEAM_ID,
    SRC:raw_json:displayName::STRING AS TEAM_NAME,
    SRC:raw_json:shortDisplayName::STRING AS SHORT_TEAM_NAME,
    SRC:raw_json:abbreviation::STRING AS ABBREVIATION,
    SRC:raw_json:name::STRING AS MASCOT,
    SRC:raw_json:location::STRING AS LOCATION,
    SRC:raw_json:groups:"$ref"::STRING AS GROUP_REF,
    SRC:raw_json:record:"$ref"::STRING AS RECORD_REF
FROM ESPN_DB.RAW.RAW_ESPN_TEAM;

/*-------------------------------------------------------------------------------
3B. Groups / Conferences / Divisions

Purpose:
  Create a readable view of ESPN group records, which are used to identify each
  team's conference and parent division.

How:
  Extracts the group name, abbreviation, and parent group reference from the raw
  group JSON.

Why:
  ESPN stores conference and division information separately from the team file.
  This view makes it possible to join teams to conferences and identify which
  teams belong to NCAA Division I.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_GROUPS_CLEAN AS
SELECT
    SRC:group_ref::STRING AS GROUP_REF,
    SRC:season::NUMBER AS SEASON,
    SRC:raw_json:id::STRING AS GROUP_ID,
    SRC:raw_json:name::STRING AS GROUP_NAME,
    SRC:raw_json:shortName::STRING AS GROUP_SHORT_NAME,
    SRC:raw_json:abbreviation::STRING AS GROUP_ABBREVIATION,
    SRC:raw_json:parent:"$ref"::STRING AS PARENT_GROUP_REF
FROM ESPN_DB.RAW.RAW_ESPN_GROUP;

/*-------------------------------------------------------------------------------
3C. Team Classification

Purpose:
  Join teams to their conference and parent division, then flag whether each team
  is an NCAA Division I team.

How:
  VW_TEAMS_CLEAN provides each team's GROUP_REF. VW_GROUPS_CLEAN maps that group
  to a conference, and the parent group maps to the broader division.

Why:
  The ESPN pull includes more than Division I teams. This view creates the D1
  flag used later to filter the analysis to teams with complete season-level
  performance data.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_TEAM_CLASSIFICATION AS
SELECT
    t.TEAM_ID,
    t.SEASON,
    t.TEAM_NAME,
    t.ABBREVIATION,
    t.LOCATION,
    t.MASCOT,
    g.GROUP_NAME AS CONFERENCE,
    pg.GROUP_NAME AS DIVISION,
    CASE
        WHEN pg.GROUP_NAME = 'NCAA Division I' THEN TRUE
        ELSE FALSE
    END AS IS_D1
FROM ESPN_DB.ANALYTICS.VW_TEAMS_CLEAN t
LEFT JOIN ESPN_DB.ANALYTICS.VW_GROUPS_CLEAN g
    ON t.GROUP_REF = g.GROUP_REF
LEFT JOIN ESPN_DB.ANALYTICS.VW_GROUPS_CLEAN pg
    ON g.PARENT_GROUP_REF = pg.GROUP_REF;

/*-------------------------------------------------------------------------------
Validation Query: Division Counts

Purpose:
  Check how many teams fall into each division and whether the D1 flag is working.

How:
  Groups teams by DIVISION and IS_D1, then counts the number of teams in each
  category.

Why:
  This validates that the team classification logic worked before using IS_D1 as
  a filter for later views.
-------------------------------------------------------------------------------*/

SELECT
    DIVISION,
    IS_D1,
    COUNT(*) AS TEAM_COUNT
FROM ESPN_DB.ANALYTICS.VW_TEAM_CLASSIFICATION
GROUP BY DIVISION, IS_D1
ORDER BY TEAM_COUNT DESC;

/*-------------------------------------------------------------------------------
3D. Team Statistics

Purpose:
  Flatten the nested ESPN record JSON into one readable row per team/stat.

How:
  RAW_ESPN_RECORD stores each team's record response inside SRC:raw_json. The query
  uses LATERAL FLATTEN twice:
    1. record_item pulls out each record type, such as total, home, road, or vsconf.
    2. stat pulls out each statistic inside that record type.

Why:
  ESPN stores performance stats in a nested JSON structure, so they need to be
  flattened before they can be used for analysis. This view creates the long-form
  stat table used to build team-level record summaries.

Note:
  COALESCE with TRY_TO_DOUBLE handles inconsistent ESPN formatting where numeric
  values sometimes appear directly and sometimes appear inside nested objects.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_RECORD_STATS_CLEAN AS
SELECT
    r.SRC:team_id::STRING AS TEAM_ID,
    r.SRC:season::NUMBER AS SEASON,
    record_item.value:type::STRING AS RECORD_TYPE,
    record_item.value:displayName::STRING AS RECORD_DISPLAY_NAME,
    stat.value:name::STRING AS STAT_NAME,
    stat.value:displayName::STRING AS STAT_DISPLAY_NAME,

    COALESCE(
        TRY_TO_DOUBLE(stat.value:value:value::STRING),
        TRY_TO_DOUBLE(stat.value:value::STRING),
        TRY_TO_DOUBLE(stat.value:displayValue::STRING)
    ) AS STAT_VALUE

FROM ESPN_DB.RAW.RAW_ESPN_RECORD r,
LATERAL FLATTEN(input => r.SRC:raw_json:items) record_item,
LATERAL FLATTEN(input => record_item.value:stats) stat;

-- Preview the flattened record-stat view to confirm that team IDs, record types,
-- stat names, and numeric values are being extracted correctly.
SELECT *
FROM ESPN_DB.ANALYTICS.VW_RECORD_STATS_CLEAN
LIMIT 10;

-- List the available record/stat combinations to understand what ESPN provides.
-- This helps confirm which stat names should be used in the team summary view.
SELECT DISTINCT
    RECORD_TYPE,
    STAT_NAME,
    STAT_DISPLAY_NAME
FROM ESPN_DB.ANALYTICS.VW_RECORD_STATS_CLEAN
ORDER BY RECORD_TYPE, STAT_NAME;

/*-------------------------------------------------------------------------------
3E. Team Records

Purpose:
  Convert the long-form record-stat view into one summary row per team.

How:
  Uses conditional aggregation to pivot key statistics into separate columns.
  For example, total wins become WINS, total losses become LOSSES, and road wins
  become AWAY_WINS.

Why:
  Team-level analysis is much easier with one row per team containing the core
  performance metrics. This view becomes the main performance table used to filter
  valid teams and support EDA.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_TEAM_RECORD_SUMMARY AS
SELECT
    TEAM_ID,
    SEASON,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'wins' THEN STAT_VALUE END) AS WINS,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'losses' THEN STAT_VALUE END) AS LOSSES,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'winPercent' THEN STAT_VALUE END) AS WIN_PCT,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'avgPointsFor' THEN STAT_VALUE END) AS PPG,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'avgPointsAgainst' THEN STAT_VALUE END) AS OPP_PPG,
    MAX(CASE WHEN RECORD_TYPE = 'total' AND STAT_NAME = 'differential' THEN STAT_VALUE END) AS POINT_DIFF,
    MAX(CASE WHEN RECORD_TYPE = 'home' AND STAT_NAME = 'wins' THEN STAT_VALUE END) AS HOME_WINS,
    MAX(CASE WHEN RECORD_TYPE = 'home' AND STAT_NAME = 'losses' THEN STAT_VALUE END) AS HOME_LOSSES,
    MAX(CASE WHEN RECORD_TYPE = 'road' AND STAT_NAME = 'wins' THEN STAT_VALUE END) AS AWAY_WINS,
    MAX(CASE WHEN RECORD_TYPE = 'road' AND STAT_NAME = 'losses' THEN STAT_VALUE END) AS AWAY_LOSSES,
    MAX(CASE WHEN RECORD_TYPE = 'vsconf' AND STAT_NAME = 'wins' THEN STAT_VALUE END) AS CONF_WINS,
    MAX(CASE WHEN RECORD_TYPE = 'vsconf' AND STAT_NAME = 'losses' THEN STAT_VALUE END) AS CONF_LOSSES
FROM ESPN_DB.ANALYTICS.VW_RECORD_STATS_CLEAN
GROUP BY TEAM_ID, SEASON;

-- Preview the team-level record summary and check whether top teams by wins look reasonable.
SELECT *
FROM ESPN_DB.ANALYTICS.VW_TEAM_RECORD_SUMMARY
ORDER BY WINS DESC NULLS LAST
LIMIT 10;

-- Check how many teams have usable season-level performance data.
-- This mirrors the Python logic that kept teams where wins was not null.
SELECT
    COUNT(*) AS TOTAL_RECORD_TEAMS,
    SUM(CASE WHEN WINS IS NOT NULL THEN 1 ELSE 0 END) AS TEAMS_WITH_WINS,
    SUM(CASE WHEN WINS IS NULL THEN 1 ELSE 0 END) AS TEAMS_MISSING_WINS
FROM ESPN_DB.ANALYTICS.VW_TEAM_RECORD_SUMMARY;

-- Compare record-stat coverage by division.
-- This validates whether non-D1 teams should be excluded from the main analysis.
SELECT
    tc.DIVISION,
    tc.IS_D1,
    COUNT(*) AS TEAM_COUNT,
    SUM(CASE WHEN rs.WINS IS NOT NULL THEN 1 ELSE 0 END) AS TEAMS_WITH_WINS,
    SUM(CASE WHEN rs.WINS IS NULL THEN 1 ELSE 0 END) AS TEAMS_MISSING_WINS
FROM ESPN_DB.ANALYTICS.VW_TEAM_CLASSIFICATION tc
LEFT JOIN ESPN_DB.ANALYTICS.VW_TEAM_RECORD_SUMMARY rs
    ON tc.TEAM_ID = rs.TEAM_ID
   AND tc.SEASON = rs.SEASON
GROUP BY tc.DIVISION, tc.IS_D1
ORDER BY TEAM_COUNT DESC;

/*-------------------------------------------------------------------------------
3F. D1 Teams

Purpose:
  Create the main team universe used for analysis.

How:
  Joins team classification data to the team record summary and filters to:
    1. Teams classified as NCAA Division I.
    2. Teams with non-null wins.

Why:
  The raw ESPN pull includes non-D1 teams, but earlier validation showed that
  non-D1 teams lack season-level performance stats. This view mirrors the Python
  filtering logic and keeps only teams with complete D1 performance data.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_D1_TEAMS AS
SELECT
    tc.TEAM_ID,
    tc.SEASON,
    tc.TEAM_NAME,
    tc.ABBREVIATION,
    tc.LOCATION,
    tc.MASCOT,
    tc.CONFERENCE,
    tc.DIVISION,
    rs.WINS,
    rs.LOSSES,
    rs.WIN_PCT,
    rs.PPG,
    rs.OPP_PPG,
    rs.POINT_DIFF,
    rs.HOME_WINS,
    rs.HOME_LOSSES,
    rs.AWAY_WINS,
    rs.AWAY_LOSSES,
    rs.CONF_WINS,
    rs.CONF_LOSSES
FROM ESPN_DB.ANALYTICS.VW_TEAM_CLASSIFICATION tc
LEFT JOIN ESPN_DB.ANALYTICS.VW_TEAM_RECORD_SUMMARY rs
    ON tc.TEAM_ID = rs.TEAM_ID
   AND tc.SEASON = rs.SEASON
WHERE tc.IS_D1 = TRUE
  AND rs.WINS IS NOT NULL;

-- Confirm the final number of D1 teams included in the analysis universe.
SELECT COUNT(*) AS D1_TEAM_COUNT
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS;

/*-------------------------------------------------------------------------------
3G. D1 Players

Purpose:
  Create a clean player-level view for only the D1 teams in the analysis universe.

How:
  Pulls player profile fields from RAW_ESPN_ATHLETE and joins to VW_D1_TEAMS
  using TEAM_ID and SEASON.

Why:
  This view supports roster composition analysis, including player position,
  height, weight, experience, hometown, and team/conference affiliation.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_D1_PLAYERS AS
SELECT
    p.SRC:athlete_id::STRING AS ATHLETE_ID,
    p.SRC:team_id::STRING AS TEAM_ID,
    p.SRC:season::NUMBER AS SEASON,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    p.SRC:raw_json:displayName::STRING AS PLAYER_NAME,
    p.SRC:raw_json:firstName::STRING AS FIRST_NAME,
    p.SRC:raw_json:lastName::STRING AS LAST_NAME,
    p.SRC:raw_json:jersey::STRING AS JERSEY,
    p.SRC:raw_json:position:abbreviation::STRING AS POSITION,
    p.SRC:raw_json:position:displayName::STRING AS POSITION_NAME,
    p.SRC:raw_json:height::FLOAT AS HEIGHT,
    p.SRC:raw_json:weight::FLOAT AS WEIGHT,
    p.SRC:raw_json:experience:displayValue::STRING AS YEAR,
    p.SRC:raw_json:experience:years::NUMBER AS YEARS_EXP,
    p.SRC:raw_json:birthPlace:city::STRING AS CITY,
    p.SRC:raw_json:birthPlace:state::STRING AS STATE,
    p.SRC:raw_json:birthPlace:country::STRING AS COUNTRY,
    p.SRC:raw_json:active::BOOLEAN AS ACTIVE
FROM ESPN_DB.RAW.RAW_ESPN_ATHLETE p
JOIN ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
    ON p.SRC:team_id::STRING = d1.TEAM_ID
   AND p.SRC:season::NUMBER = d1.SEASON;

-- Count D1 player rows to verify that athlete data successfully joins to D1 teams.
SELECT COUNT(*) AS D1_PLAYER_COUNT
FROM ESPN_DB.ANALYTICS.VW_D1_PLAYERS;

-- Preview cleaned player rows to confirm the player fields look readable.
SELECT *
FROM ESPN_DB.ANALYTICS.VW_D1_PLAYERS
LIMIT 10;

/*-------------------------------------------------------------------------------
3H. D1 Games

Purpose:
  Create a team-game view for D1 teams, where each row represents one D1 team
  in one game.

How:
  Flattens the nested schedule JSON in stages:
    1. events extracts games from each team's schedule.
    2. competitions extracts the competition object inside each game.
    3. competitors extracts the participating teams.
    4. our_team identifies the row for the team whose schedule was pulled.
    5. opponent identifies the opposing team.

Why:
  This view supports team-level game analysis, such as scoring margin, win/loss,
  home/away performance, attendance, and opponent comparisons.

Note:
  Scores are extracted using COALESCE and TRY_TO_NUMBER because ESPN sometimes
  stores scores as plain numbers and sometimes as nested value/displayValue objects.
-------------------------------------------------------------------------------*/

CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_D1_GAMES AS
WITH events AS (
    SELECT
        s.SRC:team_id::STRING AS TEAM_ID,
        s.SRC:season::NUMBER AS SEASON,
        s.SRC:season_type::NUMBER AS SEASON_TYPE,
        event.value AS EVENT_OBJ
    FROM ESPN_DB.RAW.RAW_ESPN_SCHEDULE s,
    LATERAL FLATTEN(input => s.SRC:raw_json:events) event
),

competitions AS (
    SELECT
        TEAM_ID,
        SEASON,
        SEASON_TYPE,
        EVENT_OBJ:id::STRING AS GAME_ID,
        EVENT_OBJ:date::TIMESTAMP_NTZ AS GAME_DATE,
        comp.value AS COMP_OBJ
    FROM events,
    LATERAL FLATTEN(input => EVENT_OBJ:competitions) comp
),

competitors AS (
    SELECT
        c.TEAM_ID,
        c.SEASON,
        c.SEASON_TYPE,
        c.GAME_ID,
        c.GAME_DATE,
        c.COMP_OBJ:neutralSite::BOOLEAN AS NEUTRAL_SITE,
        TRY_TO_NUMBER(c.COMP_OBJ:attendance::STRING) AS ATTENDANCE,
        competitor.value AS COMPETITOR_OBJ
    FROM competitions c,
    LATERAL FLATTEN(input => c.COMP_OBJ:competitors) competitor
),

our_team AS (
    SELECT *
    FROM competitors
    WHERE COMPETITOR_OBJ:team:id::STRING = TEAM_ID
),

opponent AS (
    SELECT *
    FROM competitors
    WHERE COMPETITOR_OBJ:team:id::STRING <> TEAM_ID
),

game_rows AS (
    SELECT DISTINCT
        o.TEAM_ID,
        o.SEASON,
        o.SEASON_TYPE,
        d1.TEAM_NAME AS TEAM,
        d1.CONFERENCE,
        o.GAME_ID,
        o.GAME_DATE AS GAME_DATE,
        opp.COMPETITOR_OBJ:team:id::STRING AS OPPONENT_ID,
        opp.COMPETITOR_OBJ:team:displayName::STRING AS OPPONENT,
        o.COMPETITOR_OBJ:homeAway::STRING AS HOME_AWAY,
        o.NEUTRAL_SITE,
        o.ATTENDANCE,
        o.COMPETITOR_OBJ:winner::BOOLEAN AS WON,

        COALESCE(
            TRY_TO_NUMBER(o.COMPETITOR_OBJ:score:value::STRING),
            TRY_TO_NUMBER(o.COMPETITOR_OBJ:score::STRING),
            TRY_TO_NUMBER(o.COMPETITOR_OBJ:score:displayValue::STRING)
        ) AS TEAM_SCORE,

        COALESCE(
            TRY_TO_NUMBER(opp.COMPETITOR_OBJ:score:value::STRING),
            TRY_TO_NUMBER(opp.COMPETITOR_OBJ:score::STRING),
            TRY_TO_NUMBER(opp.COMPETITOR_OBJ:score:displayValue::STRING)
        ) AS OPP_SCORE

    FROM our_team o
    JOIN opponent opp
        ON o.TEAM_ID = opp.TEAM_ID
       AND o.GAME_ID = opp.GAME_ID
    JOIN ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
        ON o.TEAM_ID = d1.TEAM_ID
       AND o.SEASON = d1.SEASON
)
SELECT
    TEAM_ID,
    SEASON,
    SEASON_TYPE,
    TEAM,
    CONFERENCE,
    GAME_ID,
    GAME_DATE,
    OPPONENT_ID,
    OPPONENT,
    HOME_AWAY,
    NEUTRAL_SITE,
    ATTENDANCE,
    WON,
    TEAM_SCORE,
    OPP_SCORE,
    TEAM_SCORE - OPP_SCORE AS SCORE_MARGIN
FROM game_rows;

-- Count team-game rows for D1 teams.
-- Because this is a team-game view, a game involving two D1 teams may appear twice,
-- once from each team's perspective.
SELECT COUNT(*) AS D1_GAME_ROWS
FROM ESPN_DB.ANALYTICS.VW_D1_GAMES;

-- Preview recent D1 game rows to check scores, opponents, and dates.
SELECT *
FROM ESPN_DB.ANALYTICS.VW_D1_GAMES
ORDER BY GAME_DATE DESC
LIMIT 10;

/*-------------------------------------------------------------------------------
3J. D1 Unique Games

Purpose:
  Create a game-level view where each actual game appears only once.

How:
  Starts from D1 team schedules, deduplicates events by GAME_ID, flattens the two
  competitors, ranks them within each game, and pivots them into TEAM_1 and TEAM_2
  columns.

Why:
  The team-game view is useful for team-level analysis, but this unique-game view
  is better for game-level analysis where each matchup should only count once.
  This avoids double-counting games involving two D1 teams.
-------------------------------------------------------------------------------*/
CREATE OR REPLACE VIEW ESPN_DB.ANALYTICS.VW_D1_GAMES_UNIQUE AS
WITH events AS (
    SELECT
        s.SRC:season::NUMBER AS SEASON,
        s.SRC:season_type::NUMBER AS SEASON_TYPE,
        event.value:id::STRING AS GAME_ID,
        event.value:date::TIMESTAMP_NTZ AS GAME_DATE,
        event.value AS EVENT_OBJ
    FROM ESPN_DB.RAW.RAW_ESPN_SCHEDULE s
    JOIN ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
        ON s.SRC:team_id::STRING = d1.TEAM_ID
       AND s.SRC:season::NUMBER = d1.SEASON,
    LATERAL FLATTEN(input => s.SRC:raw_json:events) event
),

deduped_events AS (
    SELECT *
    FROM events
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY GAME_ID
        ORDER BY SEASON_TYPE, GAME_DATE
    ) = 1
),

competitions AS (
    SELECT
        SEASON,
        SEASON_TYPE,
        GAME_ID,
        GAME_DATE,
        comp.value AS COMP_OBJ
    FROM deduped_events,
    LATERAL FLATTEN(input => EVENT_OBJ:competitions) comp
),

competitors AS (
    SELECT
        c.SEASON,
        c.SEASON_TYPE,
        c.GAME_ID,
        c.GAME_DATE,
        competitor.value:team:id::STRING AS TEAM_ID,
        competitor.value:team:displayName::STRING AS TEAM_NAME,

        COALESCE(
            TRY_TO_NUMBER(competitor.value:score:value::STRING),
            TRY_TO_NUMBER(competitor.value:score::STRING),
            TRY_TO_NUMBER(competitor.value:score:displayValue::STRING)
        ) AS SCORE

    FROM competitions c,
    LATERAL FLATTEN(input => c.COMP_OBJ:competitors) competitor
),

ranked_competitors AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY GAME_ID
            ORDER BY TEAM_ID
        ) AS TEAM_NUM
    FROM competitors
)

SELECT
    GAME_ID,
    SEASON,
    SEASON_TYPE,
    GAME_DATE,
    MAX(CASE WHEN TEAM_NUM = 1 THEN TEAM_ID END) AS TEAM_1_ID,
    MAX(CASE WHEN TEAM_NUM = 1 THEN TEAM_NAME END) AS TEAM_1,
    MAX(CASE WHEN TEAM_NUM = 1 THEN SCORE END) AS TEAM_1_SCORE,
    MAX(CASE WHEN TEAM_NUM = 2 THEN TEAM_ID END) AS TEAM_2_ID,
    MAX(CASE WHEN TEAM_NUM = 2 THEN TEAM_NAME END) AS TEAM_2,
    MAX(CASE WHEN TEAM_NUM = 2 THEN SCORE END) AS TEAM_2_SCORE,

    ABS(
        MAX(CASE WHEN TEAM_NUM = 1 THEN SCORE END)
        -
        MAX(CASE WHEN TEAM_NUM = 2 THEN SCORE END)
    ) AS SCORE_MARGIN

FROM ranked_competitors
GROUP BY
    GAME_ID,
    SEASON,
    SEASON_TYPE,
    GAME_DATE;

-- Preview unique games to confirm that each GAME_ID appears once with two teams and scores.
SELECT *
FROM ESPN_DB.ANALYTICS.VW_D1_GAMES_UNIQUE
ORDER BY GAME_DATE DESC
LIMIT 10;

-- Validate that the unique-game view has one row per game ID.
-- ROW_COUNT and DISTINCT_GAME_COUNT should match.
SELECT
    COUNT(*) AS ROW_COUNT,
    COUNT(DISTINCT GAME_ID) AS DISTINCT_GAME_COUNT
FROM ESPN_DB.ANALYTICS.VW_D1_GAMES_UNIQUE;
