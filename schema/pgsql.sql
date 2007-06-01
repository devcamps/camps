DROP TABLE camps;
DROP SEQUENCE camp_number;
DROP TABLE camp_users;
DROP TABLE camp_types;

CREATE SEQUENCE camp_number
INCREMENT BY 1
MAXVALUE 99
NO MINVALUE
CACHE 1
CYCLE;

CREATE TABLE camp_users (
	username	VARCHAR(32) PRIMARY KEY,
	name		VARCHAR(32) NOT NULL,
	email		VARCHAR(32) NOT NULL,
	CONSTRAINT username_valid CHECK (((username)::text ~ '^[a-z][a-z0-9_]+$'::text))
);

CREATE TABLE camp_types (
	camp_type	VARCHAR(32) PRIMARY KEY,
	description	TEXT NOT NULL DEFAULT ''
);

CREATE TABLE camps (
	camp_number	INTEGER PRIMARY KEY DEFAULT NEXTVAL('camp_number'),
	username	VARCHAR(32) NOT NULL
				CONSTRAINT camps_username_fk
				REFERENCES camp_users
				ON UPDATE CASCADE ON DELETE CASCADE,
	camp_type	VARCHAR(32) NOT NULL
				CONSTRAINT camps_camp_type_fk
				REFERENCES camp_types
				ON UPDATE CASCADE ON DELETE CASCADE,
	create_date	TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
	"comment"	TEXT NOT NULL DEFAULT ''
);

/* Add COPY statements for your environment here, setting up users, camp types, etc. */

