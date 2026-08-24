\set ON_ERROR_STOP on

-- Run once from the SSM management instance while connected as doro_admin.
-- Password values are prompted by psql and are never stored in this file.
\prompt 'store_access runtime password: ' store_access_runtime_password
\prompt 'store_access migration password: ' store_access_migration_password
\prompt 'commerce runtime password: ' commerce_runtime_password
\prompt 'commerce migration password: ' commerce_migration_password
\prompt 'payment runtime password: ' payment_runtime_password
\prompt 'payment migration password: ' payment_migration_password
\prompt 'queue runtime password: ' queue_runtime_password
\prompt 'queue migration password: ' queue_migration_password

CREATE ROLE store_access_runtime LOGIN PASSWORD :'store_access_runtime_password';
CREATE ROLE store_access_migration LOGIN PASSWORD :'store_access_migration_password';
CREATE ROLE commerce_runtime LOGIN PASSWORD :'commerce_runtime_password';
CREATE ROLE commerce_migration LOGIN PASSWORD :'commerce_migration_password';
CREATE ROLE payment_runtime LOGIN PASSWORD :'payment_runtime_password';
CREATE ROLE payment_migration LOGIN PASSWORD :'payment_migration_password';
CREATE ROLE queue_runtime LOGIN PASSWORD :'queue_runtime_password';
CREATE ROLE queue_migration LOGIN PASSWORD :'queue_migration_password';

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
