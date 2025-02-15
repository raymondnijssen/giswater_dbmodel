/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 2740

DROP FUNCTION IF EXISTS SCHEMA_NAME.gw_api_get_visit(text, p_data json);
DROP FUNCTION IF EXISTS SCHEMA_NAME.gw_api_get_visit(p_data json);
CREATE OR REPLACE FUNCTION SCHEMA_NAME.gw_fct_getvisit_main(
	p_visittype integer,
	p_data json)
    RETURNS json
    
AS $BODY$
/*EXAMPLE:

-- GET FORMS FOR WORK OFFLINE

-- unexpected first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('1', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"true", "relatedFeature":{"type":"node", "tableName":"ve_node"},"fields":{},"pageInfo":null}}$$)

-- planned first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('planned', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"true","relatedFeature":{"type":"node", "tableName":"ve_node},"fields":{},"pageInfo":null}}$$)

-- no infra first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('2', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"true","relatedFeature":{"type":""},"fields":{},"pageInfo":null}}$$)

-- modificacions de codi (a totes online i offline)
- sempre tab files
- la classe de visita es mira pel tableName no pel type
-- Els valors per defecte de classe de visita per usuari seran (només aplica a les visites online):
	visit_unspected_tablename_vdef
	visit_planned_tablename_vdef
	visit_unspected_vdef
-- Cal setejar quan inserta
-- Cal recuperar quan es peticiona una nova visita

-- RETURNING OFFLINE:
-- proposed visit_id = sempre NULL

GET ONLINE FORMS

-- unexpected first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('unexpected', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"false", "relatedFeature":{"type":"node", "id":"2074", "tableName":"ve_node"},"fields":{},"pageInfo":null}}$$)

-- planned first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('planned', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"false","relatedFeature":{"type":"node", "id":"2074", "tableName":"ve_node"},"fields":{},"pageInfo":null}}$$)

-- no infra first call
SELECT SCHEMA_NAME.gw_fct_getvisit_main('unexpected', $${"client":{"device":4,"infoType":1,"lang":"es", "cur_user":"test_user"},"form":{},
"data":{"isOffline":"false","relatedFeature":{"type":""},"fields":{},"pageInfo":null}}$$)

	
MAIN ISSUES
-----------	

LOGICS
- On click after info feature	
	- Use the visit duration parameter from param user table to choose a new visit or use the last one
	- Identify if visits exist or not
		When visit is new, 
		- choose the visitclass vdefault of user	
		When visit exists		
		- Identify if class have been changed or not -> This is especially crictic because may it affect the editable view used to upsert data

- On click without previous info (no infraestucture visit)
	- New incidency visit is showed
	
ACTIONS COULD BE DONE
- get info from existing visit
- upsert class from multievent to singlevent
- insertfile action with insert visit (visit null or visit not existing yet on database)
- change from tab data to tab files (upserting data on tabData)
- tab files
- deletefile action

*/

DECLARE

v_version text;
v_schemaname text;
v_featuretype text;
v_visitclass integer;
v_id text;
v_idname text;
v_columntype text;
v_device integer;
v_formname text;
v_tablename text;
v_fields json [];
v_fields_text text [];
v_fields_json json;
v_forminfo json;
v_formheader text;
v_formactions text;
v_formtabs text;
v_tabaux json;
v_active boolean;
v_featureid varchar ;
aux_json json;
v_tab record;
v_projecttype varchar;
v_list json;
v_activedatatab boolean;
v_activefilestab boolean;
v_client json;
v_pageinfo json;
v_layermanager json;
v_filterfields json;
v_data json;
isnewvisit boolean default false;
v_feature json;
v_addfile json;
v_deletefile json;
v_filefeature json;
v_fileid text;
v_message json;
v_message1 text;
v_message2 text;
v_message_aux text;
v_return json;
v_currentactivetab text;
v_values json;
array_index integer DEFAULT 0;
v_fieldvalue text;
v_geometry json;
v_noinfra boolean ;
v_queryinfra text ;
v_parameter text;
v_ismultievent boolean;
v_featuretablename text;
v_inputformname text;
v_isclasschanged boolean = true;  -- to identify if class of visit is changed. Important because in that case new form is reloaded with new widgets but nothing is upserted on database yet
v_visitduration text; -- to fix the duration of visit. Important because if visit is active on feature, existing visit is showed
v_status integer;  -- identifies the status of visit. Important because on status=0 visit is disabled
v_class integer;  -- identifies class of visit. Important because each class needs a diferent form
v_filterfeaturefield text;
v_visitcat integer;
v_visitextcode text;
v_startdate text;
v_incid_real_status text;
v_enddate text;
v_extvisitclass integer;
v_existvisit_id integer;
v_value text;
v_tab_data boolean;
v_offline boolean;
v_lot integer;
v_userrole text;
v_code text;
v_check_code text;
v_filter_lot_null text = '';
v_visit_id integer;
v_load_visit boolean;
v_pluginlot text;
v_returnstatus text;
v_errcontext text;
v_level integer;
v_audit_result  text;
v_returnmessage text;
v_querystring text;
v_debug_vars json;
v_debug json;
v_msgerr json;
v_new_visit boolean = FALSE;
v_new_featureid varchar;
v_new_visitclass integer;
v_tram_exec_visit integer;
v_tram_exec_visit_txt text;
v_tram_exec_visit_widget_control json;

v_emb_netejat integer;
v_emb_netejat_txt text;
v_emb_netejat_widget_control json;

rec record;
v_filter text;
v_filter_aux text;
v_unit integer;
v_count integer;
v_fields_aux json;
v_disable_widget_name text[];
v_fields_keys text[];
v_field text;
v_load_visit_aux boolean;
v_user_name text;
v_end_date text;
v_cur_user text;
v_prev_cur_user text;
v_inherit_values json;
v_column text;

BEGIN

	-- Set search path to local schema
	SET search_path = "SCHEMA_NAME", public;
	v_schemaname := 'SCHEMA_NAME';

	--  get api version
	EXECUTE 'SELECT row_to_json(row) FROM (SELECT value FROM config_param_system WHERE parameter=''admin_version'') row'
		INTO v_version;

	--check plugin lotes
	select upper(value::json->>'lotManage'::text) INTO v_pluginlot from config_param_system where parameter = 'plugin_lotmanage';

	IF v_pluginlot = 'TRUE' THEN
		v_lot = (SELECT lot_id FROM om_visit_lot_x_user WHERE endtime IS NULL AND user_id=current_user);
	END IF;

	-- fix diferent ways to say null on client
	p_data = REPLACE (p_data::text, '"NULL"', 'null');
	p_data = REPLACE (p_data::text, '"null"', 'null');
	p_data = REPLACE (p_data::text, '""', 'null');
	p_data = REPLACE (p_data::text, '''''', 'null');

	-- get project type
	SELECT project_type INTO v_projecttype FROM sys_version ORDER BY id DESC LIMIT 1;

	--  get parameters from input
	v_client = (p_data ->>'client')::json;
	v_device = ((p_data ->>'client')::json->>'device')::integer;
	v_id = ((p_data ->>'feature')::json->>'id')::integer;
	v_featureid = (((p_data ->>'data')::json->>'relatedFeature')::json->>'id');
	v_featuretype = (((p_data ->>'data')::json->>'relatedFeature')::json->>'type');
	v_activedatatab = (((p_data ->>'form')::json->>'tabData')::json->>'active')::boolean;
	v_activefilestab = (((p_data ->>'form')::json->>'tabFiles')::json->>'active')::boolean;
	v_addfile = ((p_data ->>'data')::json->>'newFile')::json;
	v_deletefile = ((p_data ->>'data')::json->>'deleteFile')::json;
	v_currentactivetab = (((p_data ->>'form')::json->>'navigation')::json->>'currentActiveTab')::text;
	v_visitclass = ((p_data ->>'data')::json->>'fields')::json->>'class_id';
	v_featuretablename = (((p_data ->>'data')::json->>'relatedFeature')::json->>'tableName');
	v_tab_data = (((p_data ->>'form')::json->>'tabData')::json->>'active')::text;
	v_offline = ((p_data ->>'data')::json->>'isOffline')::boolean;
	v_tram_exec_visit = ((p_data ->>'data')::json->>'fields')::json->>'tram_exec_visit';
	v_emb_netejat = ((p_data ->>'data')::json->>'fields')::json->>'emb_netejat';
	v_fields_aux = ((p_data ->>'data')::json->>'fields')::json;
	v_cur_user := (p_data ->> 'client')::json->> 'cur_user';
	
	v_prev_cur_user = current_user;
	IF v_cur_user IS NOT NULL THEN
		EXECUTE 'SET ROLE "'||v_cur_user||'"';
	END IF;

	--   Get editability of layer
	v_querystring = concat('SELECT r1.rolname as "role"
		FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_auth_members m
		ON (m.member = r.oid)
		JOIN pg_roles r1 ON (m.roleid=r1.oid)
		WHERE r.rolcanlogin AND r.rolname = ', quote_nullable(current_user),'
		ORDER BY 1;');
	v_debug_vars := json_build_object('current_user', current_user);
	v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 10);
	SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
	EXECUTE v_querystring INTO v_userrole;

	 -- LOTS MANAGE UNITS (um visitclass)
	 -- if feature_type is unit, we change to arc/node and select one of the elements that are in this unit

	IF v_featuretype = 'unit' THEN

		-- don't allow to visit units with orderby bigger than others that have not been visited the same day. NULLs can be visited
		IF (SELECT orderby FROM om_visit_lot_x_unit WHERE unit_id=v_featureid::integer AND lot_id=v_lot) IS NOT NULL THEN

			FOR rec IN SELECT * FROM om_visit_lot_x_unit WHERE lot_id=v_lot AND orderby<(SELECT orderby FROM om_visit_lot_x_unit WHERE unit_id=v_featureid::integer AND lot_id=v_lot)
			LOOP
				SELECT count(*) INTO v_count FROM om_visit WHERE unit_id=rec.unit_id AND lot_id=v_lot;

				IF v_count = 0 THEN
					--raise exception 'no pots visitar';
					EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
					"data":{"message":"3197", "function":"2740","debug_msg":""}}$$);'INTO v_message;

					v_message_aux = ((((v_message->>'body')::json->>'data')::json->>'info')::json->>'text')::text;
					v_message_aux := COALESCE(v_message_aux, '');
					
					EXECUTE 'SET ROLE "'||v_prev_cur_user||'"';
					
					RETURN ('{"status":"Warning", "message":"'||v_message_aux||'", "version":'||v_version||
					 ',"body":{"feature":{"featureType":"visit", "tableName":"", "idName":"visit_id", "id":""}'||
					', "form":{"formTabs":{"active":true, "fields":{}}}'
					', "data":{}}'||
					'}')::json;

				END IF;
			END LOOP;
		END IF;

		v_visitclass := (SELECT visitclass_id FROM om_visit_lot WHERE id=v_lot);

		v_unit=v_featureid;

		v_featuretype='arc';
		v_featuretablename='v_edit_arc';
		v_new_featureid=(SELECT arc_id FROM om_visit_lot_x_arc WHERE lot_id=v_lot AND unit_id=v_featureid::integer LIMIT 1);
		-- to manage unexpected lots with um's, check if unit exists without compare lot_id
		IF v_new_featureid IS NULL THEN
			v_new_featureid=(SELECT arc_id FROM om_visit_lot_x_arc WHERE unit_id=v_featureid::integer LIMIT 1);
		END IF;
		v_new_visitclass=(SELECT id FROM config_visit_class WHERE parent_id=v_visitclass AND feature_type='ARC');

		IF v_new_featureid IS NULL THEN
			v_featuretype='node';
			v_featuretablename='v_edit_node';
			v_new_featureid=(SELECT node_id FROM om_visit_lot_x_node WHERE lot_id=v_lot AND unit_id=v_featureid::integer LIMIT 1);
			-- to manage unexpected lots with um's, check if unit exists without compare lot_id
			IF v_new_featureid IS NULL THEN
				v_new_featureid=(SELECT node_id FROM om_visit_lot_x_node WHERE unit_id=v_featureid::integer LIMIT 1);
			END IF;
			v_new_visitclass=(SELECT id FROM config_visit_class WHERE parent_id=v_visitclass AND feature_type='NODE');

		END IF;

        IF v_new_featureid IS NULL THEN
			v_featuretype='gully';
			v_featuretablename='v_edit_gully';
			v_new_featureid=(SELECT gully_id FROM om_visit_lot_x_gully WHERE lot_id=v_lot AND unit_id=v_featureid::integer LIMIT 1);
			-- to manage unexpected lots with um's, check if unit exists without compare lot_id
			IF v_new_featureid IS NULL THEN
				v_new_featureid=(SELECT gully_id FROM om_visit_lot_x_gully WHERE unit_id=v_featureid::integer LIMIT 1);
			END IF;
			v_new_visitclass=(SELECT id FROM config_visit_class WHERE parent_id=v_visitclass AND feature_type='GULLY');

		END IF;

		v_featureid=v_new_featureid;
		v_visitclass=v_new_visitclass;

	END IF;

    -- get v_featuretype if is null or 'visit'(when open it from visit_manager)
	IF v_featuretype IS NULL OR v_featuretype='visit' THEN
		IF v_projecttype='WS' THEN
			SELECT feature_type, feature_id INTO v_featuretype, v_featureid FROM
				(SELECT 'node' AS feature_type, node_id AS feature_id FROM om_visit v JOIN om_visit_x_node n on n.visit_id=v.id WHERE v.id=v_id::integer
				UNION
				SELECT 'arc' AS feature_type, arc_id AS feature_id FROM om_visit v JOIN om_visit_x_arc a on a.visit_id=v.id WHERE v.id=v_id::integer
				UNION
				SELECT 'connec' AS feature_type, connec_id AS feature_id FROM om_visit v JOIN om_visit_x_connec c on c.visit_id=v.id WHERE v.id=v_id::integer)a;
		ELSE
			SELECT feature_type, feature_id INTO v_featuretype, v_featureid FROM
				(SELECT 'node' AS feature_type, node_id AS feature_id FROM om_visit v JOIN om_visit_x_node n on n.visit_id=v.id WHERE v.id=v_id::integer
				UNION
				SELECT 'arc' AS feature_type, arc_id AS feature_id FROM om_visit v JOIN om_visit_x_arc a on a.visit_id=v.id WHERE v.id=v_id::integer
				UNION
				SELECT 'gully' AS feature_type, gully_id AS feature_id FROM om_visit v JOIN om_visit_x_gully g on g.visit_id=v.id WHERE v.id=v_id::integer
				UNION
				SELECT 'connec' AS feature_type, connec_id AS feature_id FROM om_visit v JOIN om_visit_x_connec c on c.visit_id=v.id WHERE v.id=v_id::integer)a;
		END IF;

	END IF;


	--  get visitclass
	--IF v_visitclass IS NULL THEN

		IF v_featureid IS NULL THEN
			v_featureid = v_id;
		END IF;

		IF v_featuretype IS NULL AND p_visittype=1 AND v_id IS NULL THEN
			v_querystring = concat('SELECT lower(sys_type) FROM ',v_featuretablename,' LIMIT 1');
			v_debug_vars := json_build_object('v_featuretablename', v_featuretablename);
			v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 20);
			SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
			EXECUTE v_querystring INTO v_featuretype;
		END IF;

		IF v_offline THEN
			v_id = NULL;
		else

			IF v_pluginlot then
				IF v_featuretype IS NOT NULL AND v_featureid IS NOT NULL THEN

					-- getting visit class in function: 1st v_lot, 2nd feature_type
					IF v_lot IS NOT NULL AND p_visittype = 1 AND v_visitclass IS NULL THEN
						v_visitclass := (SELECT visitclass_id FROM om_visit_lot WHERE id=v_lot);
					END IF;

					IF v_visitclass IS NULL THEN
						v_visitclass := (SELECT id FROM config_visit_class WHERE visit_type=p_visittype AND feature_type = upper(v_featuretype) AND param_options->>'offlineDefault' = 'true' LIMIT 1)::integer;
					END IF;

					IF v_visitclass IS NULL THEN
						v_visitclass := (SELECT id FROM config_visit_class WHERE feature_type=upper(v_featuretype) AND visit_type=1 LIMIT 1);
					END IF;

					IF v_lot IS NOT NULL THEN
						v_filter_lot_null = concat(' AND om_visit.lot_id = ', v_lot);
					END IF;

					-- get if visit already exists
					v_querystring = concat('SELECT visit_id FROM om_visit_x_', (v_featuretype) ,'
						JOIN om_visit ON om_visit.id = om_visit_x_', (v_featuretype) ,'.visit_id
						WHERE ', (v_featuretype) ,'_id = ', quote_literal(v_featureid) ,'::text ', v_filter_lot_null ,' AND om_visit.class_id = ',v_visitclass , ' AND status not in (4,5)
						ORDER BY om_visit_x_', (v_featuretype) ,'.id desc LIMIT 1');
					v_debug_vars := json_build_object('v_featuretype', v_featuretype, 'v_featureid', v_featureid, 'v_filter_lot_null', v_filter_lot_null, 'v_visitclass', v_visitclass);
					v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 30);
					SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
					EXECUTE v_querystring INTO v_visit_id;

				END IF;
			ELSIF v_featuretype IS NOT NULL AND v_featureid IS NOT NULL THEN
				IF v_visitclass IS NULL THEN
					v_visitclass := (SELECT id FROM config_visit_class WHERE feature_type= upper(v_featuretype) order by id asc limit 1);
				END IF;
				-- get if visit already exists
				v_querystring = concat('SELECT visit_id FROM om_visit_x_',(v_featuretype) ,'
					JOIN om_visit ON om_visit.id = om_visit_x_',(v_featuretype) ,'.visit_id
					WHERE ', (v_featuretype) ,'_id = ', quote_literal(v_featureid) ,'::text  AND om_visit.class_id = ', v_visitclass ,'
					ORDER BY om_visit_x_', (v_featuretype) ,'.id desc LIMIT 1');
				v_debug_vars := json_build_object('v_featuretype', v_featuretype, 'v_featureid', v_featureid, 'v_visitclass', v_visitclass);
				v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 40);
				SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
				EXECUTE v_querystring INTO v_visit_id;
			END IF;
			-- if visit exists, get v_id and control if we have to load its form according to days interval

			IF v_visit_id IS NOT NULL THEN

				v_querystring = concat('SELECT true FROM om_visit WHERE status not in (4,5) AND id = ', quote_nullable(v_visit_id),' ORDER BY id desc LIMIT 1');
				v_debug_vars := json_build_object('v_visit_id', v_visit_id);
				v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 50);
				SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
				EXECUTE v_querystring INTO v_load_visit;

			END IF;

            IF v_visit_id IS NOT NULL AND v_id IS NULL THEN
            	v_id = v_visit_id;
            END IF;

			IF v_load_visit IS NOT TRUE THEN
				-- for getvisit HARDCODED v_id IS NOT NULL, so it's never new visit
				IF v_id IS NULL THEN
					v_new_visit=TRUE;
				ELSE
					v_new_visit=FALSE;
				END IF;
			END IF;

			IF v_tram_exec_visit IS NULL THEN
				v_tram_exec_visit=(SELECT value FROM om_visit_event WHERE visit_id = v_id::integer AND parameter_id = 'tram_exec_visit');
			END IF;

			IF v_emb_netejat IS NULL THEN
				v_emb_netejat=(SELECT value FROM om_visit_event WHERE visit_id = v_id::integer AND parameter_id = 'emb_netejat');
			END IF;

		END IF;

		--new visit
		IF v_visitclass IS NULL THEN
			IF v_id IS NULL OR (SELECT id FROM om_visit WHERE id=v_id::bigint) IS NULL THEN

				-- get vdefault visitclass
				IF v_offline THEN
					-- getting visit class in function of visit type and tablename (when tablename IS NULL then noinfra)
					v_visitclass := (SELECT id FROM config_visit_class WHERE visit_type=p_visittype AND tablename = v_featuretablename AND param_options->>'offlineDefault' = 'true' LIMIT 1)::integer;
					IF v_visitclass IS NULL THEN
						v_visitclass := (SELECT id FROM config_visit_class WHERE feature_type=upper(v_featuretype) AND visit_type=1 LIMIT 1);
					END IF;
				ELSE
					-- getting visit class in function of visit type and tablename (when tablename IS NULL then noinfra)
					IF p_visittype=1 THEN
						IF v_lot IS NOT NULL AND v_visitclass IS NULL THEN
							v_visitclass := (SELECT visitclass_id FROM om_visit_lot WHERE id=v_lot)::integer;
						ELSIF v_visitclass IS NULL THEN
							v_visitclass := (SELECT value FROM config_param_user WHERE parameter = concat('om_visit_planned_vdef_', v_featuretablename) AND cur_user=current_user)::integer;
						END IF;
					ELSIF  p_visittype=2 THEN

						IF v_featuretablename IS NOT NULL THEN
							v_visitclass := (SELECT value FROM config_param_user WHERE parameter = concat('om_visit_unspected_vdef_', v_featuretablename) AND cur_user=current_user)::integer;
						ELSE
							v_visitclass := (SELECT value FROM config_param_user WHERE parameter = concat('om_visit_noinfra_vdef') AND cur_user=current_user)::integer;
						END IF;
					END IF;

					-- Set visitclass for unexpected generic
					IF v_featuretype IS NULL THEN
						v_visitclass := (SELECT id FROM config_visit_class WHERE feature_type IS NULL AND visit_type=p_visittype LIMIT 1);
					END IF;

					IF v_visitclass IS NULL THEN
						v_visitclass := (SELECT id FROM config_visit_class WHERE feature_type=upper(v_featuretype) AND visit_type=p_visittype LIMIT 1);
					END IF;
				END IF;

			-- existing visit
			ELSIF v_load_visit AND v_id IS NULL THEN
				v_querystring = concat('SELECT class_id FROM om_visit WHERE id = ', quote_nullable(v_visit_id),' ORDER BY id desc LIMIT 1');
				v_debug_vars := json_build_object('v_visit_id', v_visit_id);
				v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 60);
				SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
				EXECUTE v_querystring INTO v_visitclass;
				v_id = v_visit_id;
			ELSE
				v_visitclass := (SELECT class_id FROM om_visit WHERE id=v_id::bigint);
			END IF;
		END IF;
	--END IF;

	/*IF v_visitclass IS NOT NULL THEN
		v_load_visit_aux = true;
	END IF;*/

	--  get formname and tablename

	v_formname := (SELECT formname FROM config_visit_class WHERE id=v_visitclass);
	v_tablename := (SELECT tablename FROM config_visit_class WHERE id=v_visitclass);
	v_ismultievent := (SELECT ismultievent FROM config_visit_class WHERE id=v_visitclass);

	-- getting provisional visit id if is new visit
	IF (SELECT id FROM om_visit WHERE id=v_id::int8) IS NULL OR v_id IS NULL THEN

        v_id := (SELECT nextval('om_visit_id_seq'));

		IF v_id IS NULL AND (SELECT count(id) FROM om_visit) = 0 THEN
			v_id=1;
		END IF;

		v_new_visit = true;

	END IF;


	-- get if visit is related to some ifraestructure element or not
	IF v_projecttype ='WS' THEN
		v_queryinfra = (SELECT feature_id FROM (SELECT arc_id as feature_id, visit_id FROM om_visit_x_arc UNION SELECT node_id, visit_id
				FROM om_visit_x_node UNION SELECT connec_id, visit_id FROM om_visit_x_connec LIMIT 1) a WHERE visit_id=v_id::int8);
	ELSIF v_projecttype ='TM' THEN
		v_queryinfra = (SELECT feature_id FROM (SELECT node_id AS feature_id, visit_id FROM om_visit_x_node LIMIT 1) a WHERE visit_id=v_id::int8);
	ELSE
		v_queryinfra = (SELECT feature_id FROM (SELECT arc_id as feature_id, visit_id FROM om_visit_x_arc UNION SELECT node_id, visit_id FROM om_visit_x_node
				UNION SELECT connec_id, visit_id FROM om_visit_x_connec UNION SELECT gully_id, visit_id FROM om_visit_x_gully LIMIT 1) a WHERE visit_id=v_id::int8);
	END IF;

	IF v_new_visit IS FALSE THEN

		v_extvisitclass := (SELECT class_id FROM om_visit WHERE id=v_id::int8);
		v_formname := (SELECT formname FROM config_visit_class WHERE id=v_extvisitclass);
		v_tablename := (SELECT tablename FROM config_visit_class WHERE id=v_extvisitclass);
		v_ismultievent := (SELECT ismultievent FROM config_visit_class WHERE id=v_extvisitclass);
		v_incid_real_status := (select t.idval from om_visit_event e join om_typevalue t on t.id=e.value and t.typevalue='incidencia_status'
								where parameter_id='emb_incid_status' and visit_id=v_id::int8);
		IF v_incid_real_status IS NULL THEN
			v_incid_real_status := (select t.idval from om_visit_event e join om_typevalue t on t.id=e.value and t.typevalue='incidencia_status'
						where parameter_id='node_incid_status' and visit_id=v_id::int8);
		END IF;


	END IF;

	-- get change class
	IF v_extvisitclass <> v_visitclass THEN

		v_isclasschanged = true;
		-- update change of class
		--UPDATE om_visit SET class_id=v_visitclass WHERE id=v_id::int8;

		-- message
		--SELECT gw_fct_getmessage(v_feature, 60) INTO v_message;
	END IF;

	-- setting values default of new visit
	IF v_new_visit THEN

		-- dynamics (last user's choice)--
		-- excode
		v_visitextcode =  (SELECT value FROM config_param_user WHERE parameter = 'om_visit_extcode_vdefault' AND cur_user=current_user)::text;
		--visitcat
		v_visitcat = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_cat_vdefault' AND cur_user=current_user)::integer;
		--code
		IF v_featureid IS NOT NULL THEN

            v_querystring = concat('SELECT feature_type FROM config_visit_class WHERE id = ', quote_nullable(v_visitclass));
            v_debug_vars := json_build_object('v_visitclass', v_visitclass);
            v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 70);
            SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
            EXECUTE v_querystring INTO v_check_code;

            IF v_check_code IS NOT NULL AND v_featuretype IS NOT NULL THEN
                v_querystring = concat('SELECT code FROM ',v_featuretablename,' WHERE ',(v_featuretype),'_id = ',quote_nullable(v_featureid),'::text');
                v_debug_vars := json_build_object('v_featuretablename', v_featuretablename, 'v_featuretype', v_featuretype, 'v_featureid', v_featureid);
                v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 80);
                SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
                EXECUTE v_querystring INTO v_code;
            END IF;
        END IF;

		IF v_pluginlot = 'TRUE' THEN
			-- lot
			v_lot = (SELECT lot_id FROM om_visit_lot_x_user WHERE endtime IS NULL AND user_id=current_user);
		END IF;

		-- statics (configured on config_param_user forcing values)--
		--status
		v_status = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_status_vdefault' AND cur_user=current_user)::integer;
		IF v_status IS NULL THEN
			v_status = 4;
		END IF;
		-- startdate
		v_startdate = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_startdate_vdefault' AND cur_user=current_user)::integer;
		IF v_startdate IS NULL THEN
			v_startdate = left (date_trunc('minute', now())::text, 16);
		END IF;
		-- enddate
		v_enddate = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_enddate_vdefault' AND cur_user=current_user)::integer;
		-- parameter on singlevisit
		v_parameter = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_parameter_vdefault' AND cur_user=current_user)::text;
		-- value for parameter on singlevisit
		v_value = (SELECT value FROM config_param_user WHERE parameter = 'om_visit_paramvalue_vdefault' AND cur_user=current_user)::text;

		-- if om_visit_paramvalue_vdefault is used as date
		IF  (SELECT value FROM config_param_system WHERE parameter = 'om_visit_parameter_value_datatype') = 'timestamp' AND v_value IS NULL THEN
			v_value = left (date_trunc('minute', now())::text, 16);
		END IF;

	END IF;

	-- Get id column
	v_querystring = concat('SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey) WHERE  i.indrelid = ',quote_nullable(v_tablename),'::regclass AND i.indisprimary');
	v_debug_vars := json_build_object('v_tablename', v_tablename);
	v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 90);
	SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
	EXECUTE v_querystring INTO v_idname;

	-- For views it suposse pk is the first column
	IF v_idname ISNULL THEN
		v_querystring = concat('SELECT a.attname FROM pg_attribute a   JOIN pg_class t on a.attrelid = t.oid  JOIN pg_namespace s on t.relnamespace = s.oid WHERE a.attnum > 0   AND NOT a.attisdropped
			AND t.relname = ',quote_nullable(v_tablename),'
			AND s.nspname = ',quote_nullable(v_schemaname),'
			AND a.attname = ''visit_id''
			ORDER BY a.attnum LIMIT 1');
		v_debug_vars := json_build_object('v_tablename', v_tablename, 'v_schemaname', v_schemaname);
		v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 100);
		SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
		EXECUTE v_querystring INTO v_idname;
	END IF;

	-- Get id column type
	v_querystring = concat('SELECT pg_catalog.format_type(a.atttypid, a.atttypmod) FROM pg_attribute a
		JOIN pg_class t on a.attrelid = t.oid
		JOIN pg_namespace s on t.relnamespace = s.oid
		WHERE a.attnum > 0
		AND NOT a.attisdropped
		AND a.attname = ',quote_nullable(v_idname),'
		AND t.relname = ',quote_nullable(v_tablename),'
		AND s.nspname = ',quote_nullable(v_schemaname),'
		ORDER BY a.attnum');
	v_debug_vars := json_build_object('v_idname', v_idname, 'v_tablename', v_tablename, 'v_schemaname', v_schemaname);
	v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 110);
	SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
	EXECUTE v_querystring INTO v_columntype;

	RAISE NOTICE '--- gw_fct_getvisit : Visit parameters: p_visittype % v_new_visit: % featuretype: %, feature_id % v_isclasschanged: % visitclass: %,  v_visit: %,  v_status %  formname: %,  tablename: %,  idname: %, columntype %, device: % ---',
							     p_visittype, v_new_visit, v_featuretype, v_featureid, v_isclasschanged, v_visitclass, v_id, v_status, v_formname, v_tablename, v_idname, v_columntype, v_device;

	-- upserting data when change from tabData to tabFile
	IF v_currentactivetab = 'tabData' AND (v_isclasschanged IS FALSE OR v_tab_data IS FALSE) AND v_status > 0 THEN

		RAISE NOTICE '--- gw_fct_getvisit: Upsert visit calling ''gw_fct_setvisit'' with : % ---', p_data;
		SELECT gw_fct_setvisit (p_data) INTO v_return;
		v_id = ((v_return->>'body')::json->>'feature')::json->>'id';
		v_message = (v_return->>'message');

		RAISE NOTICE '--- UPSERT VISIT CALLED gw_fct_setvisit WITH MESSAGE: % ---', v_message;
	END IF;

	-- manage actions

	--IF v_offline != 'true' THEN

	v_filefeature = '{"featureType":"file", "tableName":"om_visit_event_photo", "idName": "id"}';
	/*
	IF v_addfile IS NOT NULL THEN

		RAISE NOTICE '--- ACTION ADD FILE /PHOTO ---';

		-- setting input for insert files function
		v_fields_json = gw_fct_json_object_set_key((v_addfile->>'fileFields')::json,'visit_id', v_id::text);
		v_addfile = gw_fct_json_object_set_key(v_addfile, 'fileFields', v_fields_json);
		v_addfile = replace (v_addfile::text, 'fileFields', 'fields');
		v_addfile = concat('{"data":',v_addfile::text,'}');
		v_addfile = gw_fct_json_object_set_key(v_addfile, 'feature', v_filefeature);
		v_addfile = gw_fct_json_object_set_key(v_addfile, 'client', v_client);

		RAISE NOTICE '--- CALL gw_fct_setfileinsert PASSING (v_addfile): % ---', v_addfile;

		-- calling insert files function
		SELECT gw_fct_setfileinsert (v_addfile) INTO v_addfile;

		-- building message
		v_message1 = v_message::text;
		v_message = (v_addfile->>'message');
		v_message = gw_fct_json_object_set_key(v_message, 'hint', v_message1);

	ELSIF v_deletefile IS NOT NULL THEN

		-- setting input function
		v_fileid = ((v_deletefile ->>'feature')::json->>'id')::text;
		v_filefeature = gw_fct_json_object_set_key(v_filefeature, 'id', v_fileid);
		v_deletefile = gw_fct_json_object_set_key(v_deletefile, 'feature', v_filefeature);

		RAISE NOTICE '--- CALL gw_fct_setdelete PASSING (v_deletefile): % ---', v_deletefile;

		-- calling input function
		SELECT gw_fct_setdelete(v_deletefile) INTO v_deletefile;
		v_message = (v_deletefile ->>'message')::json;

	END IF;
	*/
	--END IF;

	-- WIP
	IF v_fields_aux->>'unit_id' IS NOT NULL AND v_lot IS NOT NULL THEN
		EXECUTE 'SELECT user_name, enddate FROM om_unit_intervals WHERE unit_id='||(v_fields_aux->>'unit_id')||' AND lot_id = '||v_lot||' ORDER BY startdate DESC LIMIT 1' INTO v_user_name, v_end_date;
	ELSIF v_unit IS NOT NULL THEN
		EXECUTE 'SELECT user_name, enddate FROM om_unit_intervals WHERE unit_id='||(v_unit)||' AND lot_id = '||v_lot||' ORDER BY startdate DESC LIMIT 1' INTO v_user_name, v_end_date;
	END IF;

	IF v_user_name IS NULL OR v_end_date IS NOT NULL THEN
		v_disable_widget_name = '{endvisit}';
	ELSE
		v_disable_widget_name = '{startvisit}';
	END IF;

	--  Create tabs array
	v_formtabs := '[';

		-- Data tab
		-----------
		IF v_activedatatab IS NULL AND v_activefilestab IS NULL THEN
			v_activedatatab = True;
		END IF;

		-- hide widgets tram_exec_visit
		EXECUTE 'SELECT widgetcontrols FROM config_form_fields WHERE columnname = ''tram_exec_visit'' and formname = '''||v_formname||'''' INTO v_tram_exec_visit_widget_control;

		if v_tram_exec_visit IS NOT NULL THEN

			v_filter = ((v_tram_exec_visit_widget_control->>'hideWidgets')::JSON->>'tram_exec_visit')::json->>v_tram_exec_visit::text;
			v_filter = left(v_filter, -1);
			v_filter = right(v_filter, -1);
			v_filter = replace(v_filter, '"', '''');
		ELSE

			FOR rec IN SELECT * FROM json_each_text(((v_tram_exec_visit_widget_control->>'hideWidgets')::JSON->>'tram_exec_visit')::json)
			LOOP
				v_filter_aux = rec.value;
				v_filter_aux = left(v_filter_aux, -1);
				v_filter_aux = right(v_filter_aux, -1);
				v_filter_aux = replace(v_filter_aux, '"', '''');

				v_filter = concat(v_filter_aux, ', ', v_filter);
			END LOOP;
			v_filter = left(v_filter, -2);
		END IF;

		-- hide widgets emb_netejat
		IF v_visitclass = 10 THEN
			EXECUTE 'SELECT widgetcontrols FROM config_form_fields WHERE columnname = ''emb_netejat'' and formname = '''||v_formname||'''' INTO v_emb_netejat_widget_control;

			if v_emb_netejat IS NOT NULL THEN

				v_filter = ((v_emb_netejat_widget_control->>'hideWidgets')::JSON->>'emb_netejat')::json->>v_emb_netejat::text;
				v_filter = left(v_filter, -1);
				v_filter = right(v_filter, -1);
				v_filter = replace(v_filter, '"', '''');
			ELSE

				FOR rec IN SELECT * FROM json_each_text(((v_emb_netejat_widget_control->>'hideWidgets')::JSON->>'emb_netejat')::json)
				LOOP
					v_filter_aux = rec.value;
					v_filter_aux = left(v_filter_aux, -1);
					v_filter_aux = right(v_filter_aux, -1);
					v_filter_aux = replace(v_filter_aux, '"', '''');

					v_filter = concat(v_filter_aux, ', ', v_filter);
				END LOOP;
				v_filter = left(v_filter, -2);
			END IF;
		END IF;

		IF v_activedatatab OR v_activefilestab IS NOT TRUE THEN
			IF v_new_visit THEN
				IF v_formname IS NULL THEN
					RAISE EXCEPTION 'Api is bad configured. There is no form related to tablename';
				END IF;
				RAISE NOTICE ' --- GETTING tabData DEFAULT VALUES ON NEW VISIT ---';

				SELECT gw_fct_getformfields(v_formname, 'form_visit', 'data', v_tablename, null, v_featureid, null, 'INSERT', v_filter, v_device, null) INTO v_fields;

				FOREACH aux_json IN ARRAY v_fields
				LOOP

					IF (aux_json->>'column_id') = v_disable_widget_name[1] THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
					END IF;

					-- setting feature id value
					IF (aux_json->>'columnname') = 'arc_id' OR (aux_json->>'columnname')='node_id' OR (aux_json->>'columnname')='connec_id' OR (aux_json->>'columnname') ='gully_id'
					OR (aux_json->>'columnname') ='pol_id' OR (aux_json->>'columnname') ='sys_pol_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_featureid);
						RAISE NOTICE ' --- SETTING feature id VALUE % ---',v_featureid ;

					END IF;

					-- setting code value
					IF (aux_json->>'columnname') = 'code' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_code);
						RAISE NOTICE ' --- SETTING feature id VALUE % ---',v_featureid ;

					END IF;

					-- setting visit id value
					IF (aux_json->>'columnname') = 'visit_id' AND v_offline THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', ''::text);
					ELSIF (aux_json->>'columnname') = 'visit_id'THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_id);
						RAISE NOTICE ' --- SETTING visit id VALUE % ---',v_id ;
					END IF;

					-- setting visitclass value
					IF (aux_json->>'columnname') = 'class_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_visitclass::text);
						RAISE NOTICE ' --- SETTING visitclass VALUE % ---',v_visitclass ;
					END IF;

					-- setting visitextcode value
					IF (aux_json->>'columnname') = 'ext_code' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_visitextcode::text);
						RAISE NOTICE ' --- SETTING v_visitextcode VALUE % ---',v_visitextcode ;
					END IF;

					-- setting visitcat
					IF (aux_json->>'columnname') = 'visitcat_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_visitcat::text);
						RAISE NOTICE ' --- SETTING v_visitcat VALUE % ---',v_visitcat ;
					END IF;

					-- setting lot_id
					IF (aux_json->>'columnname') = 'lot_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_lot::text);
						RAISE NOTICE ' --- SETTING v_lot VALUE % ---',v_lot ;
					END IF;

					-- setting unit_id
					IF (aux_json->>'columnname') = 'unit_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_unit::text);
						RAISE NOTICE ' --- SETTING v_unit VALUE % ---',v_unit ;
					END IF;

					-- setting startdate
					IF (aux_json->>'columnname') = 'startdate' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_startdate);
						RAISE NOTICE ' --- SETTING startdate VALUE --- now()';
					END IF;

					-- setting status
					IF (aux_json->>'columnname') = 'status' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', '4'::text);
						RAISE NOTICE ' --- SETTING status VALUE % ---', v_status;
					END IF;

					IF (aux_json->>'columnname') = 'tram_exec_visit' THEN
						IF v_tram_exec_visit IS NULL THEN
							v_tram_exec_visit_txt = COALESCE(v_tram_exec_visit::text, '');
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_tram_exec_visit_txt::text);
						ELSE
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_tram_exec_visit::text);
						END IF;
					END IF;

					IF (aux_json->>'columnname') = 'emb_netejat' THEN
						IF v_emb_netejat IS NULL THEN
							v_emb_netejat_txt = COALESCE(v_emb_netejat::text, '');
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_emb_netejat_txt::text);
						ELSE
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_emb_netejat::text);
						END IF;
					END IF;

					-- TO IMPROVE visitclass x visitclass (inherit values)
					SELECT inherit_values INTO v_inherit_values FROM config_visit_class WHERE id = v_visitclass;
					IF v_inherit_values IS NOT NULL THEN
						--FOREACH v_column in ARRAY (v_inherit_values->>'column')
						v_column = 'insp_tram_estat';
						--LOOP
							IF (aux_json->>'columnname') = v_column THEN
								-- agafem la vista de visites, el valor del feature_id amb la data de visita més recent
								/*EXECUTE 'SELECT '||v_column||' FROM '||v_inherit_values->>''table''||' WHERE '||v_inherit_values->>'idNanme'||' = v_featureid
								ORDER BY date DESC limit 1'
								INTO v_value;*/
								SELECT insp_tram_estat_v INTO v_value FROM ve_visit_tram_insp WHERE arc_id = v_featureid
								ORDER BY startdate DESC limit 1;

								-- set inherit value to form (already on config_form_fields)
								v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_value);
							END IF;
						--END LOOP;
					END IF;



					-- setting parameter in case of singleparameter visit
					IF v_ismultievent IS FALSE THEN
						IF (aux_json->>'columnname') = 'parameter_id' THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_parameter::text);
							RAISE NOTICE ' --- SETTING parameter_id VALUE % ---',v_parameter ;
						END IF;

						IF (aux_json->>'columnname') = 'value' THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_value);
							RAISE NOTICE ' --- SETTING value VALUE % ---',v_value ;
						END IF;

					END IF;

					-- WIP Manage v_fields_aux
					EXECUTE 'SELECT array_agg(a) FROM json_object_keys('''||v_fields_aux||''')a' INTO v_fields_keys;

					IF v_fields_aux::text != '{}' THEN
					FOREACH v_field IN ARRAY v_fields_keys
					LOOP
						IF (aux_json->>'widgettype')='combo' AND (aux_json->>'column_id') = v_field THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_fields_aux->>v_field);
						ELSIF (aux_json->>'column_id') = v_field THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_fields_aux->>v_field);
						END IF;
					END LOOP;
					END IF;
					-- disable visit type if project is offline
					IF (aux_json->>'columnname') = 'class_id' AND v_offline = 'true' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
					END IF;

				END LOOP;
			ELSE

				SELECT gw_fct_getformfields( v_formname, 'form_visit', 'data', v_tablename, null, v_featureid, null, 'INSERT', v_filter, v_device, null) INTO v_fields;

				RAISE NOTICE ' --- GETTING tabData VALUES ON VISIT  ---';

				-- getting values from feature
				v_querystring = concat('SELECT (row_to_json(a)) FROM
					(SELECT * FROM ',quote_ident(v_tablename),' WHERE ',quote_ident(v_idname),' = CAST(',v_id,' AS ',(v_columntype),'))a');
				v_debug_vars := json_build_object('v_tablename', v_tablename, 'v_idname', v_idname, 'v_id', v_id, 'v_columntype', v_columntype);
				v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 120);
				SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
				EXECUTE v_querystring INTO v_values;

				-- replace in case of om_visit table
				v_values = REPLACE (v_values::text, '"id":', '"visit_id":');

				-- setting values
				FOREACH aux_json IN ARRAY v_fields
				LOOP
					array_index := array_index + 1;

					v_fieldvalue := (v_values->>(aux_json->>'columnname'));
					IF (aux_json->>'column_id') = v_disable_widget_name[1] THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
					END IF;

					-- Disable widgets from visit form if user has no permisions
					IF v_userrole LIKE '%role_basic%' THEN
						v_fields[array_index] := gw_fct_json_object_set_key(v_fields[array_index], 'disabled', True);
					END IF;

					IF (aux_json->>'widgettype')='combo' THEN

						-- TO DO add new combo values for status when status = 5
						IF (aux_json->>'columnname') = 'status' AND v_fieldvalue = '5' THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'comboIds', replace(aux_json->>'comboIds', ']', ',"5"]')::json);
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'comboNames', replace(aux_json->>'comboNames', ']', ',"Validada"]')::json);
							
							FOREACH aux_json IN ARRAY v_fields 
							LOOP
								v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
							END LOOP;
							
						END IF;

						v_fields[array_index] := gw_fct_json_object_set_key(v_fields[array_index], 'selectedId', COALESCE(v_fieldvalue, ''));

						-- setting parameter in case of singleevent visit
						--IF v_ismultievent IS FALSE AND (aux_json->>'columnname') = 'parameter_id' THEN
							--v_parameter := (SELECT parameter_id FROM config_visit_parameter_action WHERE class_id=v_visitclass LIMIT 1);
							--v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_parameter::text);
						--END IF;

					ELSE
						v_fields[array_index] := gw_fct_json_object_set_key(v_fields[array_index], 'value', COALESCE(v_fieldvalue, ''));
					END IF;

					-- formating dates
					IF (aux_json->>'widgettype')='datepickertime' THEN
						v_fields[array_index] := gw_fct_json_object_set_key(v_fields[array_index], 'value', left (date_trunc('minute', v_fieldvalue::timestamp)::text, 16));
					END IF;

					-- dissable widgets if visit is status=0
					IF v_status = 0 AND (v_fields[(aux_json->>'orderby')::INT]->>'layout_id')::integer < 9 THEN
						IF (v_fields[(aux_json->>'orderby')::INT]->>'columnname')!='status' THEN
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'iseditable', false);
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', true);
						END IF;
					END IF;

					-- Disable class_id
					IF (aux_json->>'columnname') = 'class_id' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
					END IF;

					-- disable visit type if project is offline
					IF (aux_json->>'columnname') = 'class_id' AND v_offline = 'true' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'disabled', True);
					END IF;

					-- setting incid_real_status
					IF (aux_json->>'columnname') = 'incid_real_status' THEN
						v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_incid_real_status::text);
						RAISE NOTICE ' --- SETTING incid_real_status VALUE % ---', v_incid_real_status;
					END IF;

					IF (aux_json->>'columnname') = 'tram_exec_visit' THEN
						IF v_tram_exec_visit IS NULL THEN
							v_tram_exec_visit_txt = COALESCE(v_tram_exec_visit::text, '');
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_tram_exec_visit_txt::text);
						ELSE
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_tram_exec_visit::text);
						END IF;
					END IF;

					IF (aux_json->>'columnname') = 'emb_netejat' THEN
						IF v_emb_netejat IS NULL THEN
							v_emb_netejat_txt = COALESCE(v_emb_netejat::text, '');
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_emb_netejat_txt::text);
						ELSE
							v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_emb_netejat::text);
						END IF;
					END IF;


					-- WIP Manage v_fields_aux
					EXECUTE 'SELECT array_agg(a) FROM json_object_keys('''||v_fields_aux||''')a' INTO v_fields_keys;

					IF v_fields_aux::text != '{}' THEN
						FOREACH v_field IN ARRAY v_fields_keys
						LOOP
							IF (aux_json->>'widgettype')='combo' AND (aux_json->>'column_id') = v_field THEN
								v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'selectedId', v_fields_aux->>v_field);
							ELSIF (aux_json->>'column_id') = v_field THEN
								v_fields[(aux_json->>'orderby')::INT] := gw_fct_json_object_set_key(v_fields[(aux_json->>'orderby')::INT], 'value', v_fields_aux->>v_field);
							END IF;
						END LOOP;
					END IF;

				END LOOP;

			END IF;

			v_fields_json = array_to_json (v_fields);

			v_fields_json := COALESCE(v_fields_json, '{}');

			RAISE NOTICE ' --- FILLING tabData with v_fields_json  ---';


		END IF;

		SELECT * INTO v_tab FROM config_form_tabs WHERE formname='visit' AND tabname='tab_data' and device = v_device LIMIT 1;

		IF v_tab IS NULL THEN
			SELECT * INTO v_tab FROM config_form_tabs WHERE formname='visit' AND tabname='tab_data' LIMIT 1;
		END IF;

		IF v_status = 0 or v_offline = 'true' THEN
			v_tab.tabfunction = '{}';
			v_tab.tabactions = '{}';
		END IF;

		v_tabaux := json_build_object('tabName',v_tab.tabname,'tabLabel',v_tab.label, 'tooltip',v_tab.tooltip, 'tabFunction',v_tab.tabfunction::json, 'tabActions', v_tab.tabactions::json, 'active',v_activedatatab);
		v_tabaux := gw_fct_json_object_set_key(v_tabaux, 'fields', v_fields_json);
		v_formtabs := v_formtabs || v_tabaux::text;

		RAISE NOTICE ' --- BUILDING tabData with v_tabaux % ---', v_tabaux;


		-- Files tab
		------------

		--show tab only if it is not new visit or offline is true

		IF NOT v_new_visit THEN

		--IF NOT isnewvisit OR v_load_visit_aux THEN
			--filling tab (only if it's active)

			IF v_activefilestab THEN

				-- getting filterfields
				IF v_currentactivetab = 'tabFiles' THEN
					v_filterfields := ((p_data->>'data')::json->>'fields')::json;
				END IF;

				-- setting filterfields
				v_data := (p_data->>'data');
				v_data := gw_fct_json_object_set_key(v_data, 'filterFields', v_filterfields);

				-- setting filterfeaturefields using id
				v_filterfeaturefield = '{"visit_id":'||v_id||'}';
				v_data := gw_fct_json_object_set_key(v_data, 'filterFeatureField',v_filterfeaturefield);
				p_data := gw_fct_json_object_set_key(p_data, 'data', v_data);

				v_feature := '{"tableName":"om_visit_event_photo"}';

				-- setting feature
				p_data := gw_fct_json_object_set_key(p_data, 'feature', v_feature);

				--refactor tabNames
				p_data := replace (p_data::text, 'tabFeature', 'feature');

				RAISE NOTICE '--- CALLING gw_fct_getlist USING p_data: % ---', p_data;
				SELECT gw_fct_getlist (p_data) INTO v_fields_json;

				-- getting pageinfo and list values
				v_pageinfo = ((v_fields_json->>'body')::json->>'data')::json->>'pageInfo';
				v_fields_json = ((v_fields_json->>'body')::json->>'data')::json->>'fields';

				-- setting backbutton


			END IF;

			v_fields_json := COALESCE(v_fields_json, '{}');

			-- building tab
			SELECT * INTO v_tab FROM config_form_tabs WHERE formname='visit' AND tabname='tab_file' and device = v_device LIMIT 1;

			IF v_tab IS NULL THEN
				SELECT * INTO v_tab FROM config_form_tabs WHERE formname='visit' AND tabname='tab_file' LIMIT 1;
			END IF;

			IF v_status = 0 THEN
				v_tab.tabactions = '{}';
			END IF;

			v_tabaux := json_build_object('tabName',v_tab.tabname,'tabLabel',v_tab.label, 'tooltip',v_tab.tooltip, 'tabFunction', v_tab.tabfunction::json, 'tabActions', v_tab.tabactions::json, 'active', v_activefilestab);
			v_tabaux := gw_fct_json_object_set_key(v_tabaux, 'fields', v_fields_json);

			RAISE NOTICE ' --- BUILDING tabFiles with v_tabaux  ---';

			-- setting pageInfo
			v_tabaux := gw_fct_json_object_set_key(v_tabaux, 'pageInfo', v_pageinfo);
			v_formtabs := v_formtabs  || ',' || v_tabaux::text;
		END IF;

	--closing tabs array
	v_formtabs := (v_formtabs ||']');

	-- header form

	IF p_visittype = 1 AND v_new_visit IS FALSE THEN
		v_formheader :=concat('EXISTING VISIT - ',v_id);
	ELSIF p_visittype = 1 AND v_new_visit IS TRUE THEN
		v_formheader :=concat('NEW VISIT');
	ELSIF p_visittype = 2 AND v_new_visit IS FALSE THEN
		v_formheader :=concat('EXISTING INCIDENCY - ',v_id);
	ELSIF p_visittype = 2 AND v_new_visit IS TRUE THEN
		v_formheader :=concat('NEW INCIDENCY - ',v_id);
	END IF;

	-- getting geometry
	v_querystring = concat('SELECT row_to_json(a) FROM (SELECT St_AsText(St_simplify(the_geom,0)) FROM om_visit WHERE id=',quote_literal(v_id),')a');
	v_debug_vars := json_build_object('v_id', v_id);
	v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 130);
	SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
	EXECUTE v_querystring INTO v_geometry;

        IF v_new_visit IS FALSE THEN
		IF v_geometry IS NULL AND v_featuretype IS NOT NULL AND v_featureid IS NOT NULL THEN
			v_querystring = concat('SELECT row_to_json(a) FROM (SELECT St_AsText(St_simplify(the_geom,0)) FROM ',quote_ident(v_featuretype),' WHERE ',(v_featuretype),'_id::text=',quote_literal(v_featureid),'::text)a');
			v_debug_vars := json_build_object('v_featuretype', v_featuretype, 'v_featureid', v_featureid);
			v_debug := json_build_object('querystring', v_querystring, 'vars', v_debug_vars, 'funcname', 'gw_fct_getvisit_main', 'flag', 140);
			SELECT gw_fct_debugsql(v_debug) INTO v_msgerr;
			EXECUTE v_querystring INTO v_geometry;
		END IF;
	END IF;

	-- Create new form
	v_forminfo := gw_fct_json_object_set_key(v_forminfo, 'formId', 'F11'::text);
	v_forminfo := gw_fct_json_object_set_key(v_forminfo, 'formName', v_formheader);
	v_forminfo := gw_fct_json_object_set_key(v_forminfo, 'formTabs', v_formtabs::json);

	IF v_audit_result is null THEN
        v_returnstatus = 'Accepted';
        v_level = 3;
        v_returnmessage = 'Process done successfully';

    ELSE

        SELECT ((((v_audit_result::json ->> 'body')::json ->> 'data')::json ->> 'info')::json ->> 'status')::text INTO v_returnstatus;
        SELECT ((((v_audit_result::json ->> 'body')::json ->> 'data')::json ->> 'info')::json ->> 'level')::integer INTO v_level;
        SELECT ((((v_audit_result::json ->> 'body')::json ->> 'data')::json ->> 'info')::json ->> 'message')::text INTO v_returnmessage;

    END IF;

	--  Control NULL's
	v_version := COALESCE(v_version, '{}');
	v_id := COALESCE(v_id, '{}');
	v_returnmessage := COALESCE(v_returnmessage, '{}');
	v_forminfo := COALESCE(v_forminfo, '{}');
	v_tablename := COALESCE(v_tablename, '{}');
	v_layermanager := COALESCE(v_layermanager, '{}');
	v_geometry := COALESCE(v_geometry, '{}');

	-- If project is offline dont send id
	IF v_offline THEN
		v_id = '""';
	END IF;
	
	EXECUTE 'SET ROLE "'||v_prev_cur_user||'"';
	
	-- Return
	RETURN ('{"status":"Accepted", "message":"'||v_returnmessage||'", "version":'||v_version||
             ',"body":{"feature":{"featureType":"visit", "tableName":"'||v_tablename||'", "idName":"visit_id", "id":'||v_id||'}'||
		    ', "form":'||v_forminfo||
		    ', "data":{"layerManager":'||v_layermanager||
		               ',"geometry":'|| v_geometry ||'}}'||
		    '}')::json;

	-- Exception handling

	EXCEPTION WHEN OTHERS THEN
	GET STACKED DIAGNOSTICS v_errcontext = pg_exception_context;
	RETURN ('{"status":"Failed","SQLERR":' || to_json(SQLERRM) || ', "version":'|| v_version || ',"SQLSTATE":' || to_json(SQLSTATE) || ',"MSGERR": '|| to_json(v_msgerr::json ->> 'MSGERR') ||'}')::json;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;