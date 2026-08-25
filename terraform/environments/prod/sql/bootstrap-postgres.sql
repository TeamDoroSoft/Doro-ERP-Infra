\set ON_ERROR_STOP on

-- Run once from the SSM management instance while connected as doro_admin.
-- \password disables terminal echo, so credential values are not included in
-- the audited SSM session stream or stored in this file.
CREATE ROLE store_access_runtime LOGIN;
CREATE ROLE store_access_migration LOGIN;
CREATE ROLE commerce_runtime LOGIN;
CREATE ROLE commerce_migration LOGIN;
CREATE ROLE payment_runtime LOGIN;
CREATE ROLE payment_migration LOGIN;
CREATE ROLE queue_runtime LOGIN;
CREATE ROLE queue_migration LOGIN;

\echo 'Set password for store_access_runtime'
\password store_access_runtime
\echo 'Set password for store_access_migration'
\password store_access_migration
\echo 'Set password for commerce_runtime'
\password commerce_runtime
\echo 'Set password for commerce_migration'
\password commerce_migration
\echo 'Set password for payment_runtime'
\password payment_runtime
\echo 'Set password for payment_migration'
\password payment_migration
\echo 'Set password for queue_runtime'
\password queue_runtime
\echo 'Set password for queue_migration'
\password queue_migration

-- RDS administrators are not PostgreSQL superusers. Temporary membership is
-- required to assign database ownership and alter the owner's default
-- privileges. It is revoked after the bootstrap is complete.
GRANT store_access_migration TO doro_admin;
GRANT commerce_migration TO doro_admin;
GRANT payment_migration TO doro_admin;
GRANT queue_migration TO doro_admin;

CREATE DATABASE store_access_db OWNER store_access_migration;
CREATE DATABASE commerce_db OWNER commerce_migration;
CREATE DATABASE payment_db OWNER payment_migration;
CREATE DATABASE queue_db OWNER queue_migration;

REVOKE ALL ON DATABASE store_access_db FROM PUBLIC;
REVOKE ALL ON DATABASE commerce_db FROM PUBLIC;
REVOKE ALL ON DATABASE payment_db FROM PUBLIC;
REVOKE ALL ON DATABASE queue_db FROM PUBLIC;

GRANT CONNECT ON DATABASE store_access_db TO store_access_runtime;
GRANT CONNECT ON DATABASE commerce_db TO commerce_runtime;
GRANT CONNECT ON DATABASE payment_db TO payment_runtime;
GRANT CONNECT ON DATABASE queue_db TO queue_runtime;

\connect store_access_db
GRANT USAGE ON SCHEMA public TO store_access_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE store_access_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO store_access_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE store_access_migration IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO store_access_runtime;

\connect commerce_db
GRANT USAGE ON SCHEMA public TO commerce_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE commerce_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO commerce_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE commerce_migration IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO commerce_runtime;

\connect payment_db
GRANT USAGE ON SCHEMA public TO payment_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE payment_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO payment_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE payment_migration IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO payment_runtime;

\connect queue_db
GRANT USAGE ON SCHEMA public TO queue_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE queue_migration IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO queue_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE queue_migration IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO queue_runtime;

REVOKE store_access_migration FROM doro_admin;
REVOKE commerce_migration FROM doro_admin;
REVOKE payment_migration FROM doro_admin;
REVOKE queue_migration FROM doro_admin;
