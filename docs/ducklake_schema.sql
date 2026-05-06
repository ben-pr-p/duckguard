--
-- PostgreSQL database dump
--

\restrict LQamerxgZwPfL1zcza2PiiGNU9d0zaGparyXksMf4lxOVzoWtdHrjKT8kqvHEXx

-- Dumped from database version 14.22 (Homebrew)
-- Dumped by pg_dump version 14.22 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ducklake_schema_export; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ducklake_schema_export;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ducklake_column; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_column (
    column_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    table_id bigint,
    column_order bigint,
    column_name character varying,
    column_type character varying,
    initial_default character varying,
    default_value character varying,
    nulls_allowed boolean,
    parent_column bigint,
    default_value_type character varying,
    default_value_dialect character varying
);


--
-- Name: ducklake_column_mapping; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_column_mapping (
    mapping_id bigint,
    table_id bigint,
    type character varying
);


--
-- Name: ducklake_column_tag; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_column_tag (
    table_id bigint,
    column_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    key character varying,
    value character varying
);


--
-- Name: ducklake_data_file; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_data_file (
    data_file_id bigint NOT NULL,
    table_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    file_order bigint,
    path character varying,
    path_is_relative boolean,
    file_format character varying,
    record_count bigint,
    file_size_bytes bigint,
    footer_size bigint,
    row_id_start bigint,
    partition_id bigint,
    encryption_key character varying,
    mapping_id bigint,
    partial_max bigint
);


--
-- Name: ducklake_delete_file; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_delete_file (
    delete_file_id bigint NOT NULL,
    table_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    data_file_id bigint,
    path character varying,
    path_is_relative boolean,
    format character varying,
    delete_count bigint,
    file_size_bytes bigint,
    footer_size bigint,
    encryption_key character varying,
    partial_max bigint
);


--
-- Name: ducklake_file_column_stats; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_file_column_stats (
    data_file_id bigint,
    table_id bigint,
    column_id bigint,
    column_size_bytes bigint,
    value_count bigint,
    null_count bigint,
    min_value character varying,
    max_value character varying,
    contains_nan boolean,
    extra_stats character varying
);


--
-- Name: ducklake_file_partition_value; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_file_partition_value (
    data_file_id bigint,
    table_id bigint,
    partition_key_index bigint,
    partition_value character varying
);


--
-- Name: ducklake_file_variant_stats; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_file_variant_stats (
    data_file_id bigint,
    table_id bigint,
    column_id bigint,
    variant_path character varying,
    shredded_type character varying,
    column_size_bytes bigint,
    value_count bigint,
    null_count bigint,
    min_value character varying,
    max_value character varying,
    contains_nan boolean,
    extra_stats character varying
);


--
-- Name: ducklake_files_scheduled_for_deletion; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_files_scheduled_for_deletion (
    data_file_id bigint,
    path character varying,
    path_is_relative boolean,
    schedule_start timestamp with time zone
);


--
-- Name: ducklake_inlined_data_1_1; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_inlined_data_1_1 (
    row_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    id integer,
    value bytea
);


--
-- Name: ducklake_inlined_data_tables; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_inlined_data_tables (
    table_id bigint,
    table_name character varying,
    schema_version bigint
);


--
-- Name: ducklake_macro; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_macro (
    schema_id bigint,
    macro_id bigint,
    macro_name character varying,
    begin_snapshot bigint,
    end_snapshot bigint
);


--
-- Name: ducklake_macro_impl; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_macro_impl (
    macro_id bigint,
    impl_id bigint,
    dialect character varying,
    sql character varying,
    type character varying
);


--
-- Name: ducklake_macro_parameters; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_macro_parameters (
    macro_id bigint,
    impl_id bigint,
    column_id bigint,
    parameter_name character varying,
    parameter_type character varying,
    default_value character varying,
    default_value_type character varying
);


--
-- Name: ducklake_metadata; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_metadata (
    key character varying NOT NULL,
    value character varying NOT NULL,
    scope character varying,
    scope_id bigint
);


--
-- Name: ducklake_name_mapping; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_name_mapping (
    mapping_id bigint,
    column_id bigint,
    source_name character varying,
    target_field_id bigint,
    parent_column bigint,
    is_partition boolean
);


--
-- Name: ducklake_partition_column; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_partition_column (
    partition_id bigint,
    table_id bigint,
    partition_key_index bigint,
    column_id bigint,
    transform character varying
);


--
-- Name: ducklake_partition_info; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_partition_info (
    partition_id bigint,
    table_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint
);


--
-- Name: ducklake_schema; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_schema (
    schema_id bigint NOT NULL,
    schema_uuid uuid,
    begin_snapshot bigint,
    end_snapshot bigint,
    schema_name character varying,
    path character varying,
    path_is_relative boolean
);


--
-- Name: ducklake_schema_versions; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_schema_versions (
    begin_snapshot bigint,
    schema_version bigint,
    table_id bigint
);


--
-- Name: ducklake_snapshot; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_snapshot (
    snapshot_id bigint NOT NULL,
    snapshot_time timestamp with time zone,
    schema_version bigint,
    next_catalog_id bigint,
    next_file_id bigint
);


--
-- Name: ducklake_snapshot_changes; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_snapshot_changes (
    snapshot_id bigint NOT NULL,
    changes_made character varying,
    author character varying,
    commit_message character varying,
    commit_extra_info character varying
);


--
-- Name: ducklake_sort_expression; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_sort_expression (
    sort_id bigint,
    table_id bigint,
    sort_key_index bigint,
    expression character varying,
    dialect character varying,
    sort_direction character varying,
    null_order character varying
);


--
-- Name: ducklake_sort_info; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_sort_info (
    sort_id bigint,
    table_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint
);


--
-- Name: ducklake_table; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_table (
    table_id bigint,
    table_uuid uuid,
    begin_snapshot bigint,
    end_snapshot bigint,
    schema_id bigint,
    table_name character varying,
    path character varying,
    path_is_relative boolean
);


--
-- Name: ducklake_table_column_stats; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_table_column_stats (
    table_id bigint,
    column_id bigint,
    contains_null boolean,
    contains_nan boolean,
    min_value character varying,
    max_value character varying,
    extra_stats character varying
);


--
-- Name: ducklake_table_stats; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_table_stats (
    table_id bigint,
    record_count bigint,
    next_row_id bigint,
    file_size_bytes bigint
);


--
-- Name: ducklake_tag; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_tag (
    object_id bigint,
    begin_snapshot bigint,
    end_snapshot bigint,
    key character varying,
    value character varying
);


--
-- Name: ducklake_view; Type: TABLE; Schema: ducklake_schema_export; Owner: -
--

CREATE TABLE ducklake_schema_export.ducklake_view (
    view_id bigint,
    view_uuid uuid,
    begin_snapshot bigint,
    end_snapshot bigint,
    schema_id bigint,
    view_name character varying,
    dialect character varying,
    sql character varying,
    column_aliases character varying
);


--
-- Name: ducklake_data_file ducklake_data_file_pkey; Type: CONSTRAINT; Schema: ducklake_schema_export; Owner: -
--

ALTER TABLE ONLY ducklake_schema_export.ducklake_data_file
    ADD CONSTRAINT ducklake_data_file_pkey PRIMARY KEY (data_file_id);


--
-- Name: ducklake_delete_file ducklake_delete_file_pkey; Type: CONSTRAINT; Schema: ducklake_schema_export; Owner: -
--

ALTER TABLE ONLY ducklake_schema_export.ducklake_delete_file
    ADD CONSTRAINT ducklake_delete_file_pkey PRIMARY KEY (delete_file_id);


--
-- Name: ducklake_schema ducklake_schema_pkey; Type: CONSTRAINT; Schema: ducklake_schema_export; Owner: -
--

ALTER TABLE ONLY ducklake_schema_export.ducklake_schema
    ADD CONSTRAINT ducklake_schema_pkey PRIMARY KEY (schema_id);


--
-- Name: ducklake_snapshot_changes ducklake_snapshot_changes_pkey; Type: CONSTRAINT; Schema: ducklake_schema_export; Owner: -
--

ALTER TABLE ONLY ducklake_schema_export.ducklake_snapshot_changes
    ADD CONSTRAINT ducklake_snapshot_changes_pkey PRIMARY KEY (snapshot_id);


--
-- Name: ducklake_snapshot ducklake_snapshot_pkey; Type: CONSTRAINT; Schema: ducklake_schema_export; Owner: -
--

ALTER TABLE ONLY ducklake_schema_export.ducklake_snapshot
    ADD CONSTRAINT ducklake_snapshot_pkey PRIMARY KEY (snapshot_id);


--
-- PostgreSQL database dump complete
--

\unrestrict LQamerxgZwPfL1zcza2PiiGNU9d0zaGparyXksMf4lxOVzoWtdHrjKT8kqvHEXx

