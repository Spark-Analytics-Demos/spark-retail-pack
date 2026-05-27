-- =============================================================================
-- load_to_snowflake_bronze.sql
-- Loads Northwind Co. demo CSVs from an S3/GCS stage into Snowflake bronze tables.
--
-- Prerequisites:
--   1. Create an external stage pointing at your cloud storage bucket
--      containing the demo datasets (or use Snowflake's internal stage).
--   2. Replace @DEMO_STAGE with your stage name.
--   3. Run against RAW_RETAIL database with RETAIL_LOADER role.
--
-- Usage: run with SnowSQL or Snowflake Worksheets, one section at a time.
-- =============================================================================

USE ROLE RETAIL_LOADER;
USE DATABASE RAW_RETAIL;
USE WAREHOUSE RETAIL_LOAD_WH;

-- ---------------------------------------------------------------------------
-- Create a named file format for CSV ingestion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT demo_csv_fmt
  TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  DATE_FORMAT = 'AUTO'
  TIMESTAMP_FORMAT = 'AUTO'
  SKIP_BLANK_LINES = TRUE;

-- ---------------------------------------------------------------------------
-- SHOPIFY tables
-- ---------------------------------------------------------------------------
USE SCHEMA SHOPIFY;

CREATE OR REPLACE TABLE orders (
    id                                              NUMBER,
    name                                            VARCHAR,
    order_number                                    NUMBER,
    customer_id                                     NUMBER,
    created_at                                      TIMESTAMP_TZ,
    updated_at                                      TIMESTAMP_TZ,
    processed_at                                    TIMESTAMP_TZ,
    closed_at                                       TIMESTAMP_TZ,
    cancelled_at                                    TIMESTAMP_TZ,
    financial_status                                VARCHAR,
    fulfillment_status                              VARCHAR,
    email                                           VARCHAR,
    subtotal_price                                  NUMBER(18,6),
    total_discounts                                 NUMBER(18,6),
    total_tax                                       NUMBER(18,6),
    total_shipping_price_set_shop_money_amount       NUMBER(18,6),
    total_tip_received                              NUMBER(18,6),
    total_price                                     NUMBER(18,6),
    currency                                        VARCHAR,
    source_name                                     VARCHAR,
    landing_site                                    VARCHAR,
    landing_site_ref                                VARCHAR,
    cart_token                                      VARCHAR,
    note_attributes                                 VARCHAR,
    client_details_browser_width                    NUMBER,
    client_details_user_agent                       VARCHAR,
    browser_ip                                      VARCHAR,
    test                                            BOOLEAN,
    tags                                            VARCHAR,
    note                                            VARCHAR,
    discount_codes                                  VARIANT,
    shipping_address_country_code                   VARCHAR,
    shipping_address_province_code                  VARCHAR,
    billing_address_country_code                    VARCHAR
);

COPY INTO orders
FROM @DEMO_STAGE/shopify/orders.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE customers (
    id                              NUMBER,
    created_at                      TIMESTAMP_TZ,
    updated_at                      TIMESTAMP_TZ,
    email                           VARCHAR,
    first_name                      VARCHAR,
    last_name                       VARCHAR,
    phone                           VARCHAR,
    accepts_marketing               BOOLEAN,
    accepts_sms_marketing           BOOLEAN,
    state                           VARCHAR,
    default_address_country_code    VARCHAR,
    default_address_province_code   VARCHAR,
    default_address_city            VARCHAR,
    default_address_zip             VARCHAR,
    default_address_company         VARCHAR,
    tags                            VARCHAR,
    note                            VARCHAR,
    orders_count                    NUMBER,
    total_spent                     NUMBER(18,6)
);

COPY INTO customers
FROM @DEMO_STAGE/shopify/customers.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE order_line_items (
    id                  NUMBER,
    order_id            NUMBER,
    variant_id          NUMBER,
    product_id          NUMBER,
    sku                 VARCHAR,
    title               VARCHAR,
    name                VARCHAR,
    variant_title       VARCHAR,
    quantity            NUMBER,
    price               NUMBER(18,6),
    total_discount      NUMBER(18,6),
    tax_lines           VARCHAR,
    fulfillment_status  VARCHAR,
    requires_shipping   BOOLEAN,
    taxable             BOOLEAN,
    gift_card           BOOLEAN,
    properties          VARCHAR,
    vendor              VARCHAR
);

COPY INTO order_line_items
FROM @DEMO_STAGE/shopify/order_line_items.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- Add _fivetran_synced pseudo-column after load
ALTER TABLE order_line_items ADD COLUMN _fivetran_synced TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP();

CREATE OR REPLACE TABLE refunds (
    id              NUMBER,
    order_id        NUMBER,
    created_at      TIMESTAMP_TZ,
    note            VARCHAR,
    processed_at    TIMESTAMP_TZ
);

COPY INTO refunds
FROM @DEMO_STAGE/shopify/refunds.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE products (
    id              NUMBER,
    title           VARCHAR,
    handle          VARCHAR,
    product_type    VARCHAR,
    vendor          VARCHAR,
    status          VARCHAR,
    published_at    TIMESTAMP_TZ,
    image_url       VARCHAR,
    tags            VARCHAR,
    body_html       VARCHAR,
    created_at      TIMESTAMP_TZ,
    updated_at      TIMESTAMP_TZ
);

COPY INTO products
FROM @DEMO_STAGE/shopify/products.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE product_variants (
    id                  NUMBER,
    product_id          NUMBER,
    title               VARCHAR,
    sku                 VARCHAR,
    price               NUMBER(18,6),
    compare_at_price    NUMBER(18,6),
    option1             VARCHAR,
    option2             VARCHAR,
    option3             VARCHAR,
    inventory_item_id   NUMBER,
    inventory_quantity  NUMBER,
    requires_shipping   BOOLEAN,
    taxable             BOOLEAN,
    barcode             VARCHAR,
    weight              NUMBER(10,4),
    weight_unit         VARCHAR,
    created_at          TIMESTAMP_TZ,
    updated_at          TIMESTAMP_TZ
);

COPY INTO product_variants
FROM @DEMO_STAGE/shopify/product_variants.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE inventory_items (
    id                      NUMBER,
    sku                     VARCHAR,
    cost                    NUMBER(18,6),
    tracked                 BOOLEAN,
    country_code_of_origin  VARCHAR,
    created_at              TIMESTAMP_TZ,
    updated_at              TIMESTAMP_TZ
);

COPY INTO inventory_items
FROM @DEMO_STAGE/shopify/inventory_items.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE inventory_levels (
    inventory_item_id   NUMBER,
    location_id         VARCHAR,
    available           NUMBER,
    updated_at          TIMESTAMP_TZ
);

COPY INTO inventory_levels
FROM @DEMO_STAGE/shopify/inventory_levels.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE locations (
    id              VARCHAR,
    name            VARCHAR,
    active          BOOLEAN,
    address1        VARCHAR,
    city            VARCHAR,
    province        VARCHAR,
    province_code   VARCHAR,
    country_code    VARCHAR,
    zip             VARCHAR,
    phone           VARCHAR,
    updated_at      TIMESTAMP_TZ
);

COPY INTO locations
FROM @DEMO_STAGE/shopify/locations.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE transactions (
    id                  NUMBER,
    order_id            NUMBER,
    kind                VARCHAR,
    status              VARCHAR,
    created_at          TIMESTAMP_TZ,
    amount              NUMBER(18,6),
    currency            VARCHAR,
    gateway             VARCHAR,
    processed_at        TIMESTAMP_TZ,
    payment_method_type VARCHAR
);

COPY INTO transactions
FROM @DEMO_STAGE/shopify/transactions.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- ---------------------------------------------------------------------------
-- STRIPE tables
-- ---------------------------------------------------------------------------
USE SCHEMA STRIPE;

CREATE OR REPLACE TABLE charges (
    id          VARCHAR,
    created     NUMBER,   -- Unix epoch; staging converts to TIMESTAMP
    amount      NUMBER,   -- cents
    currency    VARCHAR,
    status      VARCHAR,
    livemode    BOOLEAN,
    customer    VARCHAR
);

COPY INTO charges
FROM @DEMO_STAGE/stripe/charges.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE customers (
    id      VARCHAR,
    created NUMBER,
    email   VARCHAR
);

COPY INTO customers
FROM @DEMO_STAGE/stripe/customers.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE refunds (
    id      VARCHAR,
    charge  VARCHAR,
    amount  NUMBER,
    created NUMBER
);

COPY INTO refunds
FROM @DEMO_STAGE/stripe/refunds.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE disputes (
    id      VARCHAR,
    charge  VARCHAR,
    amount  NUMBER,
    created NUMBER
);

COPY INTO disputes
FROM @DEMO_STAGE/stripe/disputes.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE payment_methods (
    id      VARCHAR,
    type    VARCHAR,
    created NUMBER
);

COPY INTO payment_methods
FROM @DEMO_STAGE/stripe/payment_methods.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- ---------------------------------------------------------------------------
-- GA4 tables
-- ---------------------------------------------------------------------------
USE SCHEMA GA4;

CREATE OR REPLACE TABLE events (
    event_date                      VARCHAR,    -- YYYYMMDD
    event_name                      VARCHAR,
    user_pseudo_id                  VARCHAR,
    user_id                         VARCHAR,
    ga_session_id                   VARCHAR,
    event_timestamp                 NUMBER,     -- microseconds since epoch
    device__category                VARCHAR,
    device__mobile_brand_name       VARCHAR,
    device__operating_system        VARCHAR,
    device__web_info__browser       VARCHAR,
    traffic_source__source          VARCHAR,
    traffic_source__medium          VARCHAR,
    traffic_source__name            VARCHAR,
    geo__country                    VARCHAR,
    geo__region                     VARCHAR,
    page_location                   VARCHAR,
    page_referrer                   VARCHAR,
    page_title                      VARCHAR,
    ecommerce__transaction_id       VARCHAR,
    ecommerce__purchase_revenue     NUMBER(18,6),
    ecommerce__currency             VARCHAR,
    engagement_time_msec            NUMBER,
    is_new_user                     BOOLEAN
);

COPY INTO events
FROM @DEMO_STAGE/ga4/events.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE users (
    user_pseudo_id      VARCHAR,
    _fivetran_synced    TIMESTAMP_TZ
);

COPY INTO users
FROM @DEMO_STAGE/ga4/users.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- ---------------------------------------------------------------------------
-- META_ADS tables
-- ---------------------------------------------------------------------------
USE SCHEMA META_ADS;

CREATE OR REPLACE TABLE daily_insights (
    date_start          DATE,
    campaign_id         VARCHAR,
    ad_set_id           VARCHAR,
    ad_id               VARCHAR,
    spend               NUMBER(18,6),
    impressions         NUMBER,
    clicks              NUMBER,
    reach               NUMBER,
    inline_link_clicks  NUMBER,
    actions             VARCHAR,   -- JSON array
    action_values       VARCHAR    -- JSON array
);

COPY INTO daily_insights
FROM @DEMO_STAGE/meta_ads/daily_insights.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE campaigns (
    id              VARCHAR,
    name            VARCHAR,
    objective       VARCHAR,
    status          VARCHAR,
    account_id      VARCHAR,
    _fivetran_synced TIMESTAMP_TZ
);

COPY INTO campaigns
FROM @DEMO_STAGE/meta_ads/campaigns.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE ad_sets (
    id              VARCHAR,
    campaign_id     VARCHAR,
    name            VARCHAR,
    status          VARCHAR,
    _fivetran_synced TIMESTAMP_TZ
);

COPY INTO ad_sets
FROM @DEMO_STAGE/meta_ads/ad_sets.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE ads (
    id              VARCHAR,
    campaign_id     VARCHAR,
    adset_id        VARCHAR,
    name            VARCHAR,
    status          VARCHAR,
    _fivetran_synced TIMESTAMP_TZ
);

COPY INTO ads
FROM @DEMO_STAGE/meta_ads/ads.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- ---------------------------------------------------------------------------
-- KLAVIYO tables
-- ---------------------------------------------------------------------------
USE SCHEMA KLAVIYO;

CREATE OR REPLACE TABLE events (
    id                  VARCHAR,
    event_name          VARCHAR,
    profile_id          VARCHAR,
    datetime            TIMESTAMP_TZ,
    campaign_id         VARCHAR,
    flow_id             VARCHAR,
    event_properties    VARIANT
);

-- event_properties is JSON string in CSV; parse after load:
CREATE OR REPLACE TEMP TABLE klaviyo_events_raw (
    id              VARCHAR,
    event_name      VARCHAR,
    profile_id      VARCHAR,
    datetime        TIMESTAMP_TZ,
    campaign_id     VARCHAR,
    flow_id         VARCHAR,
    event_properties VARCHAR
);

COPY INTO klaviyo_events_raw
FROM @DEMO_STAGE/klaviyo/events.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

INSERT INTO events
SELECT id, event_name, profile_id, datetime, campaign_id, flow_id,
       PARSE_JSON(event_properties)
FROM klaviyo_events_raw;

CREATE OR REPLACE TABLE profiles (
    id          VARCHAR,
    created     TIMESTAMP_TZ,
    email       VARCHAR,
    first_name  VARCHAR,
    last_name   VARCHAR
);

COPY INTO profiles
FROM @DEMO_STAGE/klaviyo/profiles.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE campaigns (
    id              VARCHAR,
    name            VARCHAR,
    subject         VARCHAR,
    status          VARCHAR,
    _fivetran_synced TIMESTAMP_TZ
);

COPY INTO campaigns
FROM @DEMO_STAGE/klaviyo/campaigns.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

CREATE OR REPLACE TABLE flows (
    id              VARCHAR,
    name            VARCHAR,
    status          VARCHAR,
    _fivetran_synced TIMESTAMP_TZ
);

COPY INTO flows
FROM @DEMO_STAGE/klaviyo/flows.csv
FILE_FORMAT = demo_csv_fmt
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
ON_ERROR = ABORT_STATEMENT;

-- =============================================================================
-- Verify row counts after load
-- =============================================================================
SELECT 'shopify.orders'            AS tbl, COUNT(*) AS rows FROM RAW_RETAIL.SHOPIFY.orders
UNION ALL SELECT 'shopify.customers',         COUNT(*) FROM RAW_RETAIL.SHOPIFY.customers
UNION ALL SELECT 'shopify.order_line_items',  COUNT(*) FROM RAW_RETAIL.SHOPIFY.order_line_items
UNION ALL SELECT 'shopify.products',          COUNT(*) FROM RAW_RETAIL.SHOPIFY.products
UNION ALL SELECT 'shopify.product_variants',  COUNT(*) FROM RAW_RETAIL.SHOPIFY.product_variants
UNION ALL SELECT 'shopify.inventory_items',   COUNT(*) FROM RAW_RETAIL.SHOPIFY.inventory_items
UNION ALL SELECT 'shopify.inventory_levels',  COUNT(*) FROM RAW_RETAIL.SHOPIFY.inventory_levels
UNION ALL SELECT 'stripe.charges',            COUNT(*) FROM RAW_RETAIL.STRIPE.charges
UNION ALL SELECT 'ga4.events',                COUNT(*) FROM RAW_RETAIL.GA4.events
UNION ALL SELECT 'meta_ads.daily_insights',   COUNT(*) FROM RAW_RETAIL.META_ADS.daily_insights
UNION ALL SELECT 'klaviyo.events',            COUNT(*) FROM RAW_RETAIL.KLAVIYO.events
ORDER BY 1;
