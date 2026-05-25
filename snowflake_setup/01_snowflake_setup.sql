-- =============================================================================
-- SNOWFLAKE SETUP SCRIPT
-- DBT Engineering Demo - E-Commerce Analytics
-- Run this in Snowflake BEFORE running dbt
-- =============================================================================

-- Step 1: Create warehouse, database, and schemas
CREATE WAREHOUSE IF NOT EXISTS DBT_WH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Warehouse for DBT development and testing';

CREATE DATABASE IF NOT EXISTS DBT_DEMO;
USE DATABASE DBT_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS MARTS;
CREATE SCHEMA IF NOT EXISTS SNAPSHOTS;

-- Step 2: Create role and user for dbt
CREATE ROLE IF NOT EXISTS DBT_ROLE;
GRANT USAGE ON WAREHOUSE DBT_WH TO ROLE DBT_ROLE;
GRANT ALL ON DATABASE DBT_DEMO TO ROLE DBT_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE DBT_DEMO TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE DBT_DEMO TO ROLE DBT_ROLE;
GRANT ALL ON ALL TABLES IN DATABASE DBT_DEMO TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE DBT_DEMO TO ROLE DBT_ROLE;

-- Step 3: Create raw source tables (mimicking raw ingestion layer)
USE SCHEMA RAW;

CREATE OR REPLACE TABLE RAW.CUSTOMERS (
    CUSTOMER_ID     VARCHAR(50),
    FIRST_NAME      VARCHAR(100),
    LAST_NAME       VARCHAR(100),
    EMAIL           VARCHAR(200),
    PHONE           VARCHAR(20),
    CITY            VARCHAR(100),
    STATE           VARCHAR(50),
    COUNTRY         VARCHAR(50),
    SIGNUP_DATE     VARCHAR(20),  -- raw = string, dbt will cast
    CUSTOMER_TIER   VARCHAR(20),
    IS_ACTIVE       VARCHAR(5),
    _LOADED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDERS (
    ORDER_ID        VARCHAR(50),
    CUSTOMER_ID     VARCHAR(50),
    ORDER_DATE      VARCHAR(20),
    STATUS          VARCHAR(30),
    SHIPPING_METHOD VARCHAR(30),
    PROMO_CODE      VARCHAR(50),
    DISCOUNT_PCT    VARCHAR(10),
    _LOADED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.ORDER_ITEMS (
    ORDER_ITEM_ID   VARCHAR(50),
    ORDER_ID        VARCHAR(50),
    PRODUCT_ID      VARCHAR(50),
    QUANTITY        VARCHAR(10),
    UNIT_PRICE      VARCHAR(20),
    DISCOUNT_AMT    VARCHAR(20),
    _LOADED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.PRODUCTS (
    PRODUCT_ID      VARCHAR(50),
    PRODUCT_NAME    VARCHAR(200),
    CATEGORY        VARCHAR(100),
    SUBCATEGORY     VARCHAR(100),
    COST_PRICE      VARCHAR(20),
    LIST_PRICE      VARCHAR(20),
    SUPPLIER_ID     VARCHAR(50),
    IS_ACTIVE       VARCHAR(5),
    LAUNCH_DATE     VARCHAR(20),
    _LOADED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW.PAYMENTS (
    PAYMENT_ID      VARCHAR(50),
    ORDER_ID        VARCHAR(50),
    PAYMENT_METHOD  VARCHAR(50),
    PAYMENT_STATUS  VARCHAR(30),
    AMOUNT          VARCHAR(20),
    PAYMENT_DATE    VARCHAR(20),
    _LOADED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Step 4: Insert sample data
INSERT INTO RAW.CUSTOMERS VALUES
('C001','John','Smith','john.smith@email.com','555-0101','New York','NY','USA','2022-01-15','GOLD','true',CURRENT_TIMESTAMP()),
('C002','Jane','Doe','jane.doe@email.com','555-0102','Los Angeles','CA','USA','2022-03-22','SILVER','true',CURRENT_TIMESTAMP()),
('C003','Bob','Johnson','bob.j@email.com','555-0103','Chicago','IL','USA','2021-11-08','BRONZE','true',CURRENT_TIMESTAMP()),
('C004','Alice','Williams','alice.w@email.com','555-0104','Houston','TX','USA','2023-01-05','GOLD','true',CURRENT_TIMESTAMP()),
('C005','Charlie','Brown','charlie.b@email.com','555-0105','Phoenix','AZ','USA','2022-07-19','SILVER','false',CURRENT_TIMESTAMP()),
('C006','Diana','Miller','diana.m@email.com','555-0106','Philadelphia','PA','USA','2023-04-12','BRONZE','true',CURRENT_TIMESTAMP()),
('C007','Eve','Davis','eve.d@email.com','555-0107','San Antonio','TX','USA','2021-09-30','GOLD','true',CURRENT_TIMESTAMP()),
('C008','Frank','Wilson','frank.w@email.com','555-0108','San Diego','CA','USA','2022-12-01','SILVER','true',CURRENT_TIMESTAMP()),
('C009','Grace','Moore','grace.m@email.com','555-0109','Dallas','TX','USA','2023-06-15','BRONZE','true',CURRENT_TIMESTAMP()),
('C010','Henry','Taylor','henry.t@email.com','555-0110','San Jose','CA','USA','2022-05-20','GOLD','false',CURRENT_TIMESTAMP());

INSERT INTO RAW.PRODUCTS VALUES
('P001','Laptop Pro 15"','Electronics','Computers','800.00','1299.99','S001','true','2021-06-01',CURRENT_TIMESTAMP()),
('P002','Wireless Mouse','Electronics','Accessories','12.00','29.99','S001','true','2021-06-01',CURRENT_TIMESTAMP()),
('P003','USB-C Hub 7-in-1','Electronics','Accessories','18.00','49.99','S001','true','2022-01-15',CURRENT_TIMESTAMP()),
('P004','Standing Desk','Furniture','Office','150.00','449.99','S002','true','2021-09-01',CURRENT_TIMESTAMP()),
('P005','Ergonomic Chair','Furniture','Office','200.00','549.99','S002','true','2021-09-01',CURRENT_TIMESTAMP()),
('P006','Blue Light Glasses','Accessories','Eyewear','8.00','39.99','S003','true','2022-03-10',CURRENT_TIMESTAMP()),
('P007','Noise Cancel Headphones','Electronics','Audio','80.00','199.99','S001','true','2021-12-01',CURRENT_TIMESTAMP()),
('P008','Mechanical Keyboard','Electronics','Accessories','45.00','129.99','S001','true','2022-06-15',CURRENT_TIMESTAMP()),
('P009','Monitor 27" 4K','Electronics','Displays','220.00','599.99','S001','false','2021-04-01',CURRENT_TIMESTAMP()),
('P010','Webcam 1080p','Electronics','Accessories','25.00','79.99','S001','true','2022-02-28',CURRENT_TIMESTAMP());

INSERT INTO RAW.ORDERS VALUES
('O001','C001','2023-11-15','completed','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O002','C001','2023-12-01','completed','express','SAVE10','10',CURRENT_TIMESTAMP()),
('O003','C002','2023-10-20','completed','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O004','C003','2023-11-28','shipped','standard','SAVE5','5',CURRENT_TIMESTAMP()),
('O005','C004','2023-12-05','completed','express',NULL,'0',CURRENT_TIMESTAMP()),
('O006','C004','2023-12-10','processing','overnight','VIPFREE','0',CURRENT_TIMESTAMP()),
('O007','C005','2023-09-15','returned','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O008','C006','2023-11-01','completed','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O009','C007','2023-12-08','completed','express','SAVE10','10',CURRENT_TIMESTAMP()),
('O010','C008','2023-12-12','shipped','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O011','C009','2023-11-20','completed','standard',NULL,'0',CURRENT_TIMESTAMP()),
('O012','C010','2023-10-05','cancelled','standard',NULL,'0',CURRENT_TIMESTAMP());

INSERT INTO RAW.ORDER_ITEMS VALUES
('OI001','O001','P001','1','1299.99','0.00',CURRENT_TIMESTAMP()),
('OI002','O001','P002','2','29.99','0.00',CURRENT_TIMESTAMP()),
('OI003','O002','P007','1','199.99','20.00',CURRENT_TIMESTAMP()),
('OI004','O002','P008','1','129.99','13.00',CURRENT_TIMESTAMP()),
('OI005','O003','P004','1','449.99','0.00',CURRENT_TIMESTAMP()),
('OI006','O003','P005','1','549.99','0.00',CURRENT_TIMESTAMP()),
('OI007','O004','P006','3','39.99','0.00',CURRENT_TIMESTAMP()),
('OI008','O004','P010','1','79.99','0.00',CURRENT_TIMESTAMP()),
('OI009','O005','P009','2','599.99','0.00',CURRENT_TIMESTAMP()),
('OI010','O006','P001','1','1299.99','0.00',CURRENT_TIMESTAMP()),
('OI011','O006','P003','2','49.99','0.00',CURRENT_TIMESTAMP()),
('OI012','O007','P002','1','29.99','0.00',CURRENT_TIMESTAMP()),
('OI013','O008','P008','1','129.99','0.00',CURRENT_TIMESTAMP()),
('OI014','O009','P007','2','199.99','40.00',CURRENT_TIMESTAMP()),
('OI015','O010','P004','1','449.99','0.00',CURRENT_TIMESTAMP()),
('OI016','O011','P010','2','79.99','0.00',CURRENT_TIMESTAMP()),
('OI017','O012','P001','1','1299.99','0.00',CURRENT_TIMESTAMP());

INSERT INTO RAW.PAYMENTS VALUES
('PAY001','O001','credit_card','completed','1359.97','2023-11-15',CURRENT_TIMESTAMP()),
('PAY002','O002','paypal','completed','296.98','2023-12-01',CURRENT_TIMESTAMP()),
('PAY003','O003','credit_card','completed','999.98','2023-10-20',CURRENT_TIMESTAMP()),
('PAY004','O004','debit_card','completed','199.96','2023-11-28',CURRENT_TIMESTAMP()),
('PAY005','O005','credit_card','completed','1199.98','2023-12-05',CURRENT_TIMESTAMP()),
('PAY006','O006','credit_card','pending','1399.97','2023-12-10',CURRENT_TIMESTAMP()),
('PAY007','O007','credit_card','refunded','29.99','2023-09-15',CURRENT_TIMESTAMP()),
('PAY008','O008','paypal','completed','129.99','2023-11-01',CURRENT_TIMESTAMP()),
('PAY009','O009','credit_card','completed','359.98','2023-12-08',CURRENT_TIMESTAMP()),
('PAY010','O010','debit_card','completed','449.99','2023-12-12',CURRENT_TIMESTAMP()),
('PAY011','O011','credit_card','completed','159.98','2023-11-20',CURRENT_TIMESTAMP()),
('PAY012','O012','credit_card','failed','1299.99','2023-10-05',CURRENT_TIMESTAMP());

-- Verify row counts
SELECT 'CUSTOMERS' AS tbl, COUNT(*) AS cnt FROM RAW.CUSTOMERS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM RAW.PRODUCTS
UNION ALL SELECT 'ORDERS', COUNT(*) FROM RAW.ORDERS
UNION ALL SELECT 'ORDER_ITEMS', COUNT(*) FROM RAW.ORDER_ITEMS
UNION ALL SELECT 'PAYMENTS', COUNT(*) FROM RAW.PAYMENTS;
