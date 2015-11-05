# PostgreSQL Document Storage (pg_doc_store)

This project aims to provide a document storage interface similar to what other document storage engines like MongoDB provide, but with the backing of a fully ACID complient RDBMS system.

It was originally a fork of Rob Conery's pg_doc_api (https://github.com/robconery/pg_docs_api) written in PLV8, but is my attempt do so something similar in plgsql and require no third-party libraries.

NOTE: This project is still in early development and may change core functionality significantly that could break backward compatibility and where I will have no clear extension upgrade path available. I do not recommend this for production use before version 1.x, but I'm very welcome to any testing or feedback in the mean time to see if it would even be useful for anyone in the first place.

## Requirements

PostgreSQL 9.4+ (requires jsonb type and related functions)

pgcrypto contrib module (for use in generating UUIDs)

## Installation

This code is managed as an extension. So you just have to run

    make
    make install

And then while logged into the database run

    CREATE EXTENSION pg_doc_store;

## Usage

*`create_document(p_tablename text, OUT tablename text, OUT schemaname text) RETURNS record`*

 * Creates a table used to store your documents. Contains no data.
 * Your tablename must be schema qualified
 * The table has the structure below.
    + *id* - UUID value given to each document (http://www.postgresql.org/docs/9.4/static/datatype-uuid.html). This value is also always added to the document itself.
    + *body* -  the document itself stored as jsonb
    + *search* - a tsvector column based on the values in the document used for full-text search (FTS)
    + *created_at* - a timestamp of when the document was created
    + *updated_at* - a timestamp that is updated whenever the document is updated using the function interfaces
 * Returns the schema & tablename of the document table it created
 
```
                        Table "public.mycollection"
   Column   |           Type           |             Modifiers              
------------+--------------------------+------------------------------------
 id         | uuid                     | not null default gen_random_uuid()
 body       | jsonb                    | not null
 search     | tsvector                 | 
 created_at | timestamp with time zone | not null default now()
 updated_at | timestamp with time zone | not null default now()
Indexes:
    "mycollection_pkey" PRIMARY KEY, btree (id)
    "mycollection_body_idx" gin (body jsonb_path_ops)
    "mycollection_search_idx" gin (search)
Triggers:
    mycollection_trig BEFORE INSERT OR UPDATE OF body ON mycollection FOR EACH ROW EXECUTE PROCEDURE update_search()
```

*`save_document(p_tablename text, p_doc_string jsonb) RETURNS jsonb`*

 * Save a jsonb document to the given table.
 * If the table does not exist already, it will be created
 * If an "id" key is given in the document, it will be set as the primary key value
 * If the given "id" primary key already exists, it will update that row with the given document
 * If the given "id" does not exist, that row will be added
 * If an "id" is not given, then the next value in the sequence will be used and automatically added to the document.
 * The "search" column will automatically be updated with the latest relevant FTS values based on the given document.
 * The "updated_at" column will automatically be updated to the timestamp at the time save is run.
 * The function will return a copy of the jsonb document that is given if successfully stored.
 * WARNING: Until 9.5 is released, the UPSERT used in this function is not 100% transaction safe and may result in deadlocks on a high traffic system. Use with caution.


*`find_document(p_tablename text, p_criteria jsonb, p_orderbykey text DEFAULT 'id', p_orderby text DEFAULT 'ASC') RETURNS SETOF jsonb`*

 * Searches the given table for documents that contain the given jsonb string and returns the full document(s).
 * It's pretty much the equivalent of the @> operator when used with two jsonb values.
 * p_orderbykey allows you to tell it to sort the returned documents by the given key name.
 * p_orderby allows you to tell it which order to return that sort in. Valid values are "ASC" (the default)  and "DESC".


*`search_document(p_tablename text, p_query text) RETURNS SETOF jsonb`*

 * Performs a full-text search on the given document table for documents containing the given string in their values.
 * Returns the full jsonb document(s) ranked by relevance.


LICENSE AND COPYRIGHT
---------------------

PG Document Storage (pg_doc_store) is released under the PostgreSQL License, a liberal Open Source license, similar to the BSD or MIT licenses.

Copyright (c) 2015 Keith Fiske

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
