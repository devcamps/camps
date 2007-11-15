DROP TABLE camps;
DROP SEQUENCE camp_number;
DROP TABLE vcs_types;
DROP TABLE camp_users;
DROP TABLE camp_types;

CREATE SEQUENCE camp_number
INCREMENT 1
START 10
MINVALUE 10
MAXVALUE 99
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

CREATE TABLE vcs_types (
	vcs_type character varying(32) NOT NULL PRIMARY KEY,
	description text DEFAULT ''::text NOT NULL
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
	"comment"	TEXT NOT NULL DEFAULT '',
	vcs_type	VARCHAR(32) NOT NULL
				CONSTRAINT camps_vcs_type_fk
				REFERENCES vcs_types
				ON UPDATE CASCADE ON DELETE CASCADE
);

COPY vcs_types (vcs_type, description) FROM stdin;
svn	Subversion
svk	SVK
git	Git
\.

/* Add COPY statements for your environment here, setting up users, camp types, etc. */

