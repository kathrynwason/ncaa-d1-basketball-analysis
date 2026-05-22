/*===============================================================================
REQUIRED SQL ANALYSIS QUERIES

Purpose:
  Use the cleaned D1 views to run analysis queries that satisfy the SQL rubric.

Why:
  Earlier sections create the clean analysis views. This section uses those views
  to answer basketball-relevant questions about team performance, conference
  strength, game outcomes, and roster characteristics while clearly demonstrating
  GROUP BY, joins, window functions, and subqueries.
===============================================================================*/

/*-------------------------------------------------------------------------------
1. GROUP BY Query #1: Conference Performance Summary

What:
  Summarizes overall D1 team performance by conference.

How:
  Groups D1 teams by conference and calculates average win percentage, point
  differential, points scored, and points allowed.

Why:
  This identifies which conferences appear strongest based on team-level results.
-------------------------------------------------------------------------------*/

SELECT
    CONFERENCE,
    COUNT(*) AS TEAM_COUNT,
    AVG(WIN_PCT) AS AVG_WIN_PCT,
    AVG(POINT_DIFF) AS AVG_POINT_DIFF,
    AVG(PPG) AS AVG_PPG,
    AVG(OPP_PPG) AS AVG_OPP_PPG
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
GROUP BY CONFERENCE
ORDER BY AVG_POINT_DIFF DESC NULLS LAST;

-- Output: 31 conference rows. Power conferences (SEC, Big 12, ACC, Big Ten) occupy the top 4
-- spots by average point differential, ranging from +4.7 to +5.8. Mid-majors cluster between
-- +1 and +3. The bottom conferences (SWAC, MEAC) average negative point differentials,
-- confirming a clear talent stratification across D1.

/*-------------------------------------------------------------------------------
2. GROUP BY Query #2: Conference Scoring Profile

What:
  Compares scoring profiles across conferences.

How:
  Groups D1 teams by conference and calculates average points scored, points
  allowed, and scoring margin.

Why:
  This helps evaluate whether stronger conferences are driven more by offense,
  defense, or overall scoring margin.
-------------------------------------------------------------------------------*/

SELECT
    CONFERENCE,
    COUNT(*) AS TEAM_COUNT,
    AVG(PPG) AS AVG_PPG,
    AVG(OPP_PPG) AS AVG_OPP_PPG,
    AVG(POINT_DIFF) AS AVG_POINT_DIFF,
    AVG(PPG - OPP_PPG) AS AVG_CALCULATED_MARGIN
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
GROUP BY CONFERENCE
ORDER BY AVG_POINT_DIFF DESC NULLS LAST;

-- Output: 31 conference rows. Power conferences lead in both scoring margin and raw PPG,
-- with the SEC averaging 82.9 PPG (highest in D1) while the Big 12 leads in win rate despite
-- scoring less. The AVG_POINT_DIFF and AVG_CALCULATED_MARGIN columns are nearly identical,
-- confirming the ESPN record-level point differential is consistent with the calculated
-- difference from raw scores. Bottom conferences (SWAC, MEAC) average negative margins and 
-- the lowest scoring totals in D1.

/*-------------------------------------------------------------------------------
3. WINDOW FUNCTION Query #1: Overall Team Ranking by Point Differential

What:
  Ranks all D1 teams by point differential.

How:
  Uses RANK() OVER ordered by point differential descending.

Why:
  Point differential is a useful strength metric because it reflects scoring
  dominance, not just wins and losses.
-------------------------------------------------------------------------------*/

SELECT
    TEAM_ID,
    TEAM_NAME,
    CONFERENCE,
    WINS,
    LOSSES,
    WIN_PCT,
    POINT_DIFF,
    RANK() OVER (ORDER BY POINT_DIFF DESC NULLS LAST) AS POINT_DIFF_RANK
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
ORDER BY POINT_DIFF_RANK;

-- Output: 362 rows covering all D1 teams. High Point Panthers lead with +18.4 point
-- differential despite playing in the Big South, followed by Gonzaga (+18.1) and Duke (+18.0).
-- Michigan (national champion) ranks 4th at +17.8. Arizona and Saint Louis round out the top 6.
-- The bottom of the list is dominated by smaller conference programs — Mississippi Valley State
-- (-18.8), Air Force (-18.4), and Gardner-Webb (-17.4) have the worst margins. Notable mid-major
-- overperformers include High Point, Miami (OH) at +14.1, and McNeese at +12.9.
-- Query is limited to top 25 in the SELECT but full output shown here for reference.

/*-------------------------------------------------------------------------------
4. WINDOW FUNCTION Query #2: Top Teams Within Each Conference

What:
  Finds the top three teams in each conference.

How:
  Uses ROW_NUMBER() partitioned by conference and ordered by win percentage and
  point differential.

Why:
  This compares teams against their conference peers rather than the entire D1
  universe.
-------------------------------------------------------------------------------*/

SELECT
    TEAM_ID,
    TEAM_NAME,
    CONFERENCE,
    WINS,
    LOSSES,
    WIN_PCT,
    POINT_DIFF,
    ROW_NUMBER() OVER (
        PARTITION BY CONFERENCE
        ORDER BY WIN_PCT DESC NULLS LAST, POINT_DIFF DESC NULLS LAST
    ) AS CONFERENCE_RANK
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
QUALIFY CONFERENCE_RANK <= 3
ORDER BY CONFERENCE, CONFERENCE_RANK;

-- Output: 93 rows — top 3 teams per conference across all 31 conferences. Michigan leads the
-- Big Ten at 37-3, Arizona leads the Big 12 at 36-3, and Duke leads the ACC at 35-3. Notable
-- mid-major conference leaders include High Point (Big South, 31-5), Gonzaga (WCC, 31-4), and
-- McNeese (Southland, 28-6). The MEAC is the weakest conference by this measure — its top team
-- Howard wins at only a 0.686 clip.

/*-------------------------------------------------------------------------------
5. SUBQUERY Query #1: Teams Above Average Point Differential

What:
  Identifies teams with point differential above the D1 average.

How:
  Uses a non-correlated scalar subquery in the WHERE clause to calculate the
  overall D1 average point differential.

Why:
  This filters for teams that outperform the national D1 scoring-margin benchmark.
-------------------------------------------------------------------------------*/

SELECT
    TEAM_ID,
    TEAM_NAME,
    CONFERENCE,
    POINT_DIFF,
    WIN_PCT
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
WHERE POINT_DIFF > (
    SELECT AVG(POINT_DIFF)
    FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
)
ORDER BY POINT_DIFF DESC;

-- Output: 185 rows — teams with point differential above the D1 average of +1.66.
-- High Point (+18.4), Gonzaga (+18.1), and Duke (+18.0) lead the list. The cutoff falls
-- around +1.7, meaning just over half of D1 teams (185 of 362) outperform the average margin.
-- Notable mid-major programs above average include High Point, Miami (OH), McNeese, Belmont,
-- and Utah Valley — demonstrating that strong performance is not exclusive to power conferences.
-- The subquery calculates the D1 average dynamically so the threshold updates automatically
-- if the underlying data changes.

/*-------------------------------------------------------------------------------
6. GROUP BY Query #3: Unique Game Scoring Summary by Season Type

What:
  Summarizes unique games by season type without double-counting games.

How:
  Uses the unique-game view, where each GAME_ID appears once, and groups by
  season type to calculate game count, average total score, and average margin.

Why:
  This checks game-level scoring patterns while avoiding duplicate team-game rows.
-------------------------------------------------------------------------------*/

SELECT
    SEASON_TYPE,
    COUNT(*) AS UNIQUE_GAME_COUNT,
    AVG(TEAM_1_SCORE + TEAM_2_SCORE) AS AVG_TOTAL_SCORE,
    AVG(SCORE_MARGIN) AS AVG_SCORE_MARGIN
FROM ESPN_DB.ANALYTICS.VW_D1_GAMES_UNIQUE
WHERE TEAM_1_SCORE IS NOT NULL
  AND TEAM_2_SCORE IS NOT NULL
GROUP BY SEASON_TYPE
ORDER BY SEASON_TYPE;

-- Output: 2 rows — regular season (type 2) and postseason (type 3).
-- Regular season produced 6,204 unique games averaging 149.7 total points and a 14.9 point
-- margin. Postseason produced 105 games averaging 150.4 total points and a 12.9 point margin.
-- Total scoring is nearly identical between regular season and postseason, but postseason games
-- are slightly closer on average — a 1.9 point reduction in margin — consistent with the
-- expectation that tournament fields are more evenly matched than the full regular season field.

/*-------------------------------------------------------------------------------
7. JOIN Query #1: Roster Features Joined to Team Performance

What:
  Combines roster characteristics with team-level performance.

How:
  Joins D1 teams to D1 players, then aggregates roster size, average height,
  average weight, and average experience by team.

Why:
  Roster composition is included as a supporting feature set for later EDA and
  modeling, while the main analysis remains focused on team and game performance.
-------------------------------------------------------------------------------*/

SELECT
    d1.TEAM_ID,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    d1.WIN_PCT,
    d1.POINT_DIFF,
    COUNT(p.ATHLETE_ID) AS ROSTER_SIZE,
    AVG(p.HEIGHT) AS AVG_HEIGHT,
    AVG(p.WEIGHT) AS AVG_WEIGHT,
    AVG(p.YEARS_EXP) AS AVG_YEARS_EXP
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
LEFT JOIN ESPN_DB.ANALYTICS.VW_D1_PLAYERS p
    ON d1.TEAM_ID = p.TEAM_ID
   AND d1.SEASON = p.SEASON
GROUP BY
    d1.TEAM_ID,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    d1.WIN_PCT,
    d1.POINT_DIFF
ORDER BY d1.POINT_DIFF DESC NULLS LAST;

-- Output: 362 rows — one per D1 team with roster characteristics joined to performance.
-- Roster sizes range from 12 to 25 players. Elite teams like Duke (25 players) and Navy
-- (25 players) carry larger rosters while many mid-majors carry 13-15. Average height across
-- all teams clusters tightly around 77-79 inches regardless of conference or win rate,
-- suggesting height alone is not a strong differentiator. Average weight ranges from roughly
-- 190 to 222 lbs. Experience averages between 2.0 and 3.5 years across most programs.
-- The bottom programs (Mississippi Valley State, Air Force, Gardner-Webb) show no consistent
-- roster profile differences from elite teams, indicating that roster physical attributes are
-- weak predictors of winning.

/*-------------------------------------------------------------------------------
8. JOIN Query #2: Game Outcomes Joined to Team Performance

What:
  Summarizes game-level outcomes for each D1 team.

How:
  Joins D1 teams to the team-game view and aggregates game count, average margin,
  average team score, and average opponent score.

Why:
  This connects season-level team strength to game-level scoring outcomes.
-------------------------------------------------------------------------------*/

SELECT
    d1.TEAM_ID,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    d1.WIN_PCT,
    d1.POINT_DIFF,
    COUNT(g.GAME_ID) AS GAME_ROWS,
    AVG(g.SCORE_MARGIN) AS AVG_GAME_MARGIN,
    AVG(g.TEAM_SCORE) AS AVG_TEAM_SCORE,
    AVG(g.OPP_SCORE) AS AVG_OPP_SCORE
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
LEFT JOIN ESPN_DB.ANALYTICS.VW_D1_GAMES g
    ON d1.TEAM_ID = g.TEAM_ID
   AND d1.SEASON = g.SEASON
WHERE g.TEAM_SCORE IS NOT NULL
GROUP BY
    d1.TEAM_ID,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    d1.WIN_PCT,
    d1.POINT_DIFF
ORDER BY AVG_GAME_MARGIN DESC NULLS LAST;

-- Output: 362 rows — one per D1 team with game-level scoring joined to season performance.
-- High Point leads with an average game margin of +18.5, followed by Gonzaga (+18.1) and
-- Duke (+18.0), consistent with the season-level point differential rankings. Game counts
-- range from 27 to 40 games per team reflecting schedule length variation across conferences.
-- The AVG_GAME_MARGIN column closely mirrors the season-level POINT_DIFF, confirming the
-- two metrics are consistent with each other. At the bottom, Mississippi Valley State averages
-- -18.8 per game and Air Force -18.3, while Gardner-Webb allows 85.5 points per game on
-- average — the highest opponent scoring in D1.

/*-------------------------------------------------------------------------------
9. WINDOW FUNCTION Query #3: Team Performance Quartiles

What:
  Splits D1 teams into four quartiles based on point differential.

How:
  Uses NTILE(4) over teams ordered by point differential descending.

Why:
  Quartiles create a simple performance tier feature that can be used for EDA,
  such as comparing top, middle, and bottom-performing teams.
-------------------------------------------------------------------------------*/

SELECT
    TEAM_ID,
    TEAM_NAME,
    CONFERENCE,
    POINT_DIFF,
    WIN_PCT,
    NTILE(4) OVER (
        ORDER BY POINT_DIFF DESC NULLS LAST
    ) AS POINT_DIFF_QUARTILE
FROM ESPN_DB.ANALYTICS.VW_D1_TEAMS
ORDER BY POINT_DIFF_QUARTILE, POINT_DIFF DESC NULLS LAST;

-- Output: 362 rows split into 4 quartiles of ~90-91 teams each based on point differential.
-- Quartile 1 (best): point diff from +5.5 to +18.4, average win rate ~0.69. Dominated by
-- power conference teams but includes notable mid-majors like High Point, Miami (OH), McNeese,
-- Belmont, and Utah Valley.
-- Quartile 2 (above average): point diff from +1.7 to +5.5, average win rate ~0.56. Mixed
-- conference representation with most teams winning slightly more than they lose.
-- Quartile 3 (below average): point diff from -2.2 to +1.7, average win rate ~0.47. Teams
-- hovering around .500 with no clear conference pattern.
-- Quartile 4 (worst): point diff from -2.2 to -18.8, average win rate ~0.34. Bottom quartile
-- is heavily represented by smaller conferences — SWAC, MEAC, Northeast, Southland — with
-- Mississippi Valley State (-18.8) and Air Force (-18.4) at the extreme low end.

/*-------------------------------------------------------------------------------
10. SUBQUERY Query #2: Teams Above Average Game Margin

What:
  Identifies D1 teams whose average game-level score margin is above the D1 average.

How:
  First aggregates game rows by team in a subquery, then compares each team's
  average game margin to the overall average game margin from another subquery.

Why:
  This connects game-level outcomes to team strength and keeps the analysis
  centered on performance rather than roster composition alone.
-------------------------------------------------------------------------------*/

SELECT
    team_margins.TEAM_ID,
    d1.TEAM_NAME,
    d1.CONFERENCE,
    d1.WIN_PCT,
    d1.POINT_DIFF,
    team_margins.AVG_GAME_MARGIN
FROM (
    SELECT
        TEAM_ID,
        SEASON,
        AVG(SCORE_MARGIN) AS AVG_GAME_MARGIN
    FROM ESPN_DB.ANALYTICS.VW_D1_GAMES
    WHERE TEAM_SCORE IS NOT NULL
      AND OPP_SCORE IS NOT NULL
    GROUP BY TEAM_ID, SEASON
) team_margins
JOIN ESPN_DB.ANALYTICS.VW_D1_TEAMS d1
    ON team_margins.TEAM_ID = d1.TEAM_ID
   AND team_margins.SEASON = d1.SEASON
WHERE team_margins.AVG_GAME_MARGIN > (
    SELECT AVG(avg_margin)
    FROM (
        SELECT
            TEAM_ID,
            SEASON,
            AVG(SCORE_MARGIN) AS avg_margin
        FROM ESPN_DB.ANALYTICS.VW_D1_GAMES
        WHERE TEAM_SCORE IS NOT NULL
          AND OPP_SCORE IS NOT NULL
        GROUP BY TEAM_ID, SEASON
    )
)
ORDER BY team_margins.AVG_GAME_MARGIN DESC;

-- Output: 184 rows — teams whose average game-level score margin exceeds the D1 average of
-- approximately +1.66 points per game. Results mirror the season-level point differential
-- rankings closely, confirming that game-level margin and season-level point differential
-- are consistent metrics. High Point (+18.5), Gonzaga (+18.1), and Duke (+18.0) lead the list.
-- The query uses two layers of subqueries: an inner derived table to calculate per-team average
-- game margin, and a scalar subquery to calculate the D1-wide average margin for comparison.
-- Notable finding: Southern Jaguars (SWAC) appear at the bottom of the above-average list
-- with a +1.68 margin despite a .500 win rate, while teams like Cornell (+5.1) and Youngstown
-- State (+4.9) are above average despite sub-.600 win rates, suggesting some teams win margins
-- without accumulating wins efficiently.