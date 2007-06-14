DROP TABLE camp_numbers;
DROP TABLE camps;
DROP TABLE camp_users;
DROP TABLE camp_types;

CREATE TABLE camp_users (
	username	VARCHAR(32) PRIMARY KEY,
	name		VARCHAR(32) NOT NULL,
	email		VARCHAR(32) NOT NULL,
	CHECK (username REGEXP '^[a-z][a-z0-9_]+$')
) ENGINE=InnoDB;

CREATE TABLE camp_types (
	camp_type	VARCHAR(32) PRIMARY KEY,
	description	TEXT NOT NULL DEFAULT ''
) ENGINE=InnoDB;

CREATE TABLE camps (
	camp_number	INTEGER PRIMARY KEY,
	username	VARCHAR(32) NOT NULL
				REFERENCES camp_users (username)
				ON UPDATE CASCADE
				ON DELETE CASCADE,
	camp_type	VARCHAR(32) NOT NULL
				REFERENCES camp_types (camp_type)
				ON UPDATE CASCADE
				ON DELETE CASCADE,
	create_date	DATETIME NOT NULL,
	comment TEXT NOT NULL DEFAULT '',
	CHECK (create_date NOT REGEXP '^0000')
) ENGINE=InnoDB;

/* Since MySQL doesn't have sequences, and it's quite difficult to have a reliable query that finds the lowest
   available camp number, we'll use this dummy table populated with numbers 1-99, which we can join against
   to find the lowest available value. */

CREATE TABLE camp_numbers (
	number	INTEGER PRIMARY KEY
	CHECK (number > 0 AND number < 100)
) ENGINE=InnoDB;

INSERT INTO camp_numbers VALUES (1);
INSERT INTO camp_numbers VALUES (2);
INSERT INTO camp_numbers VALUES (3);
INSERT INTO camp_numbers VALUES (4);
INSERT INTO camp_numbers VALUES (5);
INSERT INTO camp_numbers VALUES (6);
INSERT INTO camp_numbers VALUES (7);
INSERT INTO camp_numbers VALUES (8);
INSERT INTO camp_numbers VALUES (9);
INSERT INTO camp_numbers VALUES (10);
INSERT INTO camp_numbers VALUES (11);
INSERT INTO camp_numbers VALUES (12);
INSERT INTO camp_numbers VALUES (13);
INSERT INTO camp_numbers VALUES (14);
INSERT INTO camp_numbers VALUES (15);
INSERT INTO camp_numbers VALUES (16);
INSERT INTO camp_numbers VALUES (17);
INSERT INTO camp_numbers VALUES (18);
INSERT INTO camp_numbers VALUES (19);
INSERT INTO camp_numbers VALUES (20);
INSERT INTO camp_numbers VALUES (21);
INSERT INTO camp_numbers VALUES (22);
INSERT INTO camp_numbers VALUES (23);
INSERT INTO camp_numbers VALUES (24);
INSERT INTO camp_numbers VALUES (25);
INSERT INTO camp_numbers VALUES (26);
INSERT INTO camp_numbers VALUES (27);
INSERT INTO camp_numbers VALUES (28);
INSERT INTO camp_numbers VALUES (29);
INSERT INTO camp_numbers VALUES (30);
INSERT INTO camp_numbers VALUES (31);
INSERT INTO camp_numbers VALUES (32);
INSERT INTO camp_numbers VALUES (33);
INSERT INTO camp_numbers VALUES (34);
INSERT INTO camp_numbers VALUES (35);
INSERT INTO camp_numbers VALUES (36);
INSERT INTO camp_numbers VALUES (37);
INSERT INTO camp_numbers VALUES (38);
INSERT INTO camp_numbers VALUES (39);
INSERT INTO camp_numbers VALUES (40);
INSERT INTO camp_numbers VALUES (41);
INSERT INTO camp_numbers VALUES (42);
INSERT INTO camp_numbers VALUES (43);
INSERT INTO camp_numbers VALUES (44);
INSERT INTO camp_numbers VALUES (45);
INSERT INTO camp_numbers VALUES (46);
INSERT INTO camp_numbers VALUES (47);
INSERT INTO camp_numbers VALUES (48);
INSERT INTO camp_numbers VALUES (49);
INSERT INTO camp_numbers VALUES (50);
INSERT INTO camp_numbers VALUES (51);
INSERT INTO camp_numbers VALUES (52);
INSERT INTO camp_numbers VALUES (53);
INSERT INTO camp_numbers VALUES (54);
INSERT INTO camp_numbers VALUES (55);
INSERT INTO camp_numbers VALUES (56);
INSERT INTO camp_numbers VALUES (57);
INSERT INTO camp_numbers VALUES (58);
INSERT INTO camp_numbers VALUES (59);
INSERT INTO camp_numbers VALUES (60);
INSERT INTO camp_numbers VALUES (61);
INSERT INTO camp_numbers VALUES (62);
INSERT INTO camp_numbers VALUES (63);
INSERT INTO camp_numbers VALUES (64);
INSERT INTO camp_numbers VALUES (65);
INSERT INTO camp_numbers VALUES (66);
INSERT INTO camp_numbers VALUES (67);
INSERT INTO camp_numbers VALUES (68);
INSERT INTO camp_numbers VALUES (69);
INSERT INTO camp_numbers VALUES (70);
INSERT INTO camp_numbers VALUES (71);
INSERT INTO camp_numbers VALUES (72);
INSERT INTO camp_numbers VALUES (73);
INSERT INTO camp_numbers VALUES (74);
INSERT INTO camp_numbers VALUES (75);
INSERT INTO camp_numbers VALUES (76);
INSERT INTO camp_numbers VALUES (77);
INSERT INTO camp_numbers VALUES (78);
INSERT INTO camp_numbers VALUES (79);
INSERT INTO camp_numbers VALUES (80);
INSERT INTO camp_numbers VALUES (81);
INSERT INTO camp_numbers VALUES (82);
INSERT INTO camp_numbers VALUES (83);
INSERT INTO camp_numbers VALUES (84);
INSERT INTO camp_numbers VALUES (85);
INSERT INTO camp_numbers VALUES (86);
INSERT INTO camp_numbers VALUES (87);
INSERT INTO camp_numbers VALUES (88);
INSERT INTO camp_numbers VALUES (89);
INSERT INTO camp_numbers VALUES (90);
INSERT INTO camp_numbers VALUES (91);
INSERT INTO camp_numbers VALUES (92);
INSERT INTO camp_numbers VALUES (93);
INSERT INTO camp_numbers VALUES (94);
INSERT INTO camp_numbers VALUES (95);
INSERT INTO camp_numbers VALUES (96);
INSERT INTO camp_numbers VALUES (97);
INSERT INTO camp_numbers VALUES (98);
INSERT INTO camp_numbers VALUES (99);

/* Add INSERT statements for your environment here, setting up users, camp types, etc. */

