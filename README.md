# What Separates Winners? A Data-Driven Analysis of NCAA Division I Men's Basketball (2026)

## Overview
This project analyzes the 2025–26 NCAA Division I men's basketball season using data 
collected from the ESPN API. The analysis covers 362 D1 programs, 11,954 completed games, 
and 5,648 rostered players to identify what measurable factors separate winning programs 
from losing ones.

## Repository Structure

| File | Description |
|------|-------------|
| `ncaa_d1_basketball_analysis.ipynb` | Main analysis notebook — EDA, feature engineering, and modeling |
| `sql_analysis_queries.sql` | Standalone SQL analysis queries with comments and output summaries |
| `pipeline/00_create_jsonl.ipynb` | Pulls data from the ESPN API and writes raw JSONL files |
| `pipeline/01_create_sql_views.sql` | Creates cleaned Snowflake views from raw JSONL-loaded tables |
| `data/raw/` | Raw JSONL files output by the data collection pipeline |
| `outputs/` | CSV exports of all 10 SQL query results for reference |

## Reproducing the Analysis

1. Run `pipeline/00_create_jsonl.ipynb` to pull data from the ESPN API
2. Load the JSONL files into Snowflake and run `pipeline/01_create_sql_views.sql` to create views
3. Create a `.env` file with Snowflake credentials (see below)
4. Run `ncaa_d1_basketball_analysis.ipynb` end to end

## Environment Setup

Create a `.env` file in the project root with the following variables:

```
SNOWFLAKE_USER=your_user
SNOWFLAKE_PASSWORD=your_password
SNOWFLAKE_ACCOUNT=your_account
SNOWFLAKE_WAREHOUSE=your_warehouse
SNOWFLAKE_DATABASE=your_database
SNOWFLAKE_SCHEMA=your_schema
```

## Data Source
All data collected via the ESPN Core and Site APIs for the 2025–26 season.