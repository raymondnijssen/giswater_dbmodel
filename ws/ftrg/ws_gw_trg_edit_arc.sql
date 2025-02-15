/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 1302

CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_trg_edit_arc()
  RETURNS trigger AS
$BODY$
DECLARE 
v_inp_table varchar;
v_man_table varchar;
v_sql varchar;
v_code_autofill_bool boolean;
v_count integer;
v_promixity_buffer double precision;
v_edit_enable_arc_nodes_update boolean;
v_link_path varchar;
v_new_arc_type text;
v_old_arc_type text;
v_customfeature text;
v_addfields record;
v_new_value_param text;
v_old_value_param text;
v_featurecat text;
v_streetaxis text;
v_streetaxis2 text;
v_force_delete boolean;
v_autoupdate_fluid boolean;

BEGIN

	EXECUTE 'SET search_path TO '||quote_literal(TG_TABLE_SCHEMA)||', public';
	        v_man_table:= TG_ARGV[0];

	--modify values for custom view inserts	
	IF v_man_table IN (SELECT id FROM cat_feature) THEN
		v_customfeature:=v_man_table;
		v_man_table:=(SELECT man_table FROM cat_feature_arc c JOIN sys_feature_cat s ON c.type = s.id WHERE c.id=v_man_table);
	END IF;

	v_promixity_buffer = (SELECT "value" FROM config_param_system WHERE "parameter"='edit_feature_buffer_on_mapzone');
	v_edit_enable_arc_nodes_update = (SELECT "value" FROM config_param_system WHERE "parameter"='edit_arc_enable nodes_update');
    v_autoupdate_fluid = (SELECT value::boolean FROM config_param_system WHERE parameter='edit_connect_autoupdate_fluid');

	IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
		-- transforming streetaxis name into id
		v_streetaxis = (SELECT id FROM v_ext_streetaxis WHERE (muni_id = NEW.muni_id OR muni_id IS NULL) AND descript = NEW.streetname LIMIT 1);
		v_streetaxis2 = (SELECT id FROM v_ext_streetaxis WHERE (muni_id = NEW.muni_id OR muni_id IS NULL) AND descript = NEW.streetname2 LIMIT 1);
	END IF;

	
	IF TG_OP = 'INSERT' THEN
    
		-- Arc ID
		IF NEW.arc_id != (SELECT last_value::text FROM urn_id_seq) OR NEW.arc_id IS NULL THEN
			NEW.arc_id = (SELECT nextval('urn_id_seq'));
		END IF;

		-- Arc catalog ID
		IF (NEW.arccat_id IS NULL) THEN
			IF ((SELECT COUNT(*) FROM cat_arc WHERE active IS TRUE) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"1020", "function":"1302","debug_msg":null}}$$);';
			END IF; 

			-- get vdefault values using config user values
			IF v_customfeature IS NOT NULL THEN
				NEW.arccat_id:= (SELECT "value" FROM config_param_user WHERE "parameter"=lower(concat(v_customfeature,'_vdefault')) AND "cur_user"="current_user"() LIMIT 1);
			ELSE
				NEW.arccat_id:= (SELECT "value" FROM config_param_user WHERE "parameter"='edit_arccat_vdefault' AND "cur_user"="current_user"() LIMIT 1);

				-- get first value (last chance)
				IF (NEW.arccat_id IS NULL) THEN
					NEW.arccat_id := (SELECT id FROM cat_arc WHERE active IS TRUE LIMIT 1);
				END IF;    
			END IF;

			-- get values using proximity
			IF (NEW.arccat_id IS NULL) THEN
				NEW.arccat_id := (SELECT arccat_id from arc WHERE ST_DWithin(NEW.the_geom, arc.the_geom,0.001) LIMIT 1);
			END IF;

			IF (NEW.arccat_id IS NULL) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"1088", "function":"1302","debug_msg":null}}$$);';
			END IF;
		END IF;
		
		
		 -- Set EPA type
		IF (NEW.epa_type IS NULL) THEN
			NEW.epa_type = 'PIPE';   
		END IF;
		
		
		-- Exploitation
		IF (NEW.expl_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM exploitation WHERE active IS TRUE) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1110", "function":"1302","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.expl_id IS NULL) THEN
				NEW.expl_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_exploitation_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.expl_id IS NULL) THEN
				SELECT count(*)into v_count FROM exploitation WHERE ST_DWithin(NEW.the_geom, exploitation.the_geom,0.001) AND active IS TRUE;
				IF v_count = 1 THEN
					NEW.expl_id = (SELECT expl_id FROM exploitation WHERE ST_DWithin(NEW.the_geom, exploitation.the_geom,0.001) AND active IS TRUE LIMIT 1);
				ELSE
					NEW.expl_id =(SELECT expl_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.expl_id IS NULL) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"2012", "function":"1302","debug_msg":"'||NEW.arc_id::text||'"}}$$);';
			END IF;            
		END IF;
		
		
		-- Sector ID
		IF (NEW.sector_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM sector WHERE active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1008", "function":"1302","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.sector_id IS NULL) THEN
				NEW.sector_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_sector_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.sector_id IS NULL) THEN
				SELECT count(*)into v_count FROM sector WHERE ST_DWithin(NEW.the_geom, sector.the_geom,0.001) AND active IS TRUE;
				IF v_count = 1 THEN
					NEW.sector_id = (SELECT sector_id FROM sector WHERE ST_DWithin(NEW.the_geom, sector.the_geom,0.001) AND active IS TRUE LIMIT 1);
				ELSE
					NEW.sector_id =(SELECT sector_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.sector_id IS NULL) THEN
				NEW.sector_id =0;
			END IF;            
		END IF;
		
		
		-- Dma ID
		IF (NEW.dma_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM dma WHERE active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"1012", "function":"1302","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.dma_id IS NULL) THEN
				NEW.dma_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_dma_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.dma_id IS NULL) THEN
				SELECT count(*)into v_count FROM dma WHERE ST_DWithin(NEW.the_geom, dma.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.dma_id = (SELECT dma_id FROM dma WHERE ST_DWithin(NEW.the_geom, dma.the_geom,0.001) AND active IS TRUE LIMIT 1);
				ELSE
					NEW.dma_id =(SELECT dma_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.dma_id IS NULL) THEN
				NEW.dma_id =0;
			END IF;            
		END IF;
			
			
		-- Presszone
		IF (NEW.presszone_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM presszone WHERE active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"3106", "function":"1302","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.presszone_id IS NULL) THEN
				NEW.presszone_id := (SELECT "value" FROM config_param_user WHERE "parameter"='presszone_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.presszone_id IS NULL) THEN
				SELECT count(*)into v_count FROM presszone WHERE ST_DWithin(NEW.the_geom, presszone.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.presszone_id = (SELECT presszone_id FROM presszone WHERE ST_DWithin(NEW.the_geom, presszone.the_geom,0.001) AND active IS TRUE  LIMIT 1);
				ELSE
					NEW.presszone_id =(SELECT presszone_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer)
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.presszone_id IS NULL) THEN
				NEW.presszone_id =0;
			END IF;            
		END IF;
		
		-- Municipality 
		IF (NEW.muni_id IS NULL) THEN
			
			-- control error without any mapzones defined on the table of mapzone
			IF ((SELECT COUNT(*) FROM ext_municipality WHERE  active IS TRUE ) = 0) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
		       	"data":{"message":"3110", "function":"1302","debug_msg":null}}$$);';
			END IF;
			
			-- getting value default
			IF (NEW.muni_id IS NULL) THEN
				NEW.muni_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_municipality_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
			
			-- getting value from geometry of mapzone
			IF (NEW.muni_id IS NULL) THEN
				SELECT count(*)into v_count FROM ext_municipality WHERE ST_DWithin(NEW.the_geom, ext_municipality.the_geom,0.001) AND active IS TRUE ;
				IF v_count = 1 THEN
					NEW.muni_id = (SELECT muni_id FROM ext_municipality WHERE ST_DWithin(NEW.the_geom, ext_municipality.the_geom,0.001) 
					AND active IS TRUE LIMIT 1);
				ELSE
					NEW.muni_id =(SELECT muni_id FROM v_edit_arc WHERE ST_DWithin(NEW.the_geom, v_edit_arc.the_geom, v_promixity_buffer) 
					order by ST_Distance (NEW.the_geom, v_edit_arc.the_geom) LIMIT 1);
				END IF;	
			END IF;
			
			-- control error when no value
			IF (NEW.muni_id IS NULL) THEN
				EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"2024", "function":"1302","debug_msg":"'||NEW.arc_id::text||'"}}$$);';
			END IF;            
		END IF;
		
		
		-- State
		IF (NEW.state IS NULL) THEN
		    NEW.state := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_state_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;

		-- State_type
		IF (NEW.state=0) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_0_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		ELSIF (NEW.state=1) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_1_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		ELSIF (NEW.state=2) THEN
			IF (NEW.state_type IS NULL) THEN
				NEW.state_type := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_statetype_2_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			END IF;
		END IF;

			--check relation state - state_type
		IF NEW.state_type NOT IN (SELECT id FROM value_state_type WHERE state = NEW.state) THEN
			IF NEW.state IS NOT NULL THEN
				v_sql = NEW.state;
			ELSE
				v_sql = 'null';
			END IF;
			EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
			"data":{"message":"3036", "function":"1318","debug_msg":"'||v_sql::text||'"}}$$);';
		END IF;

		--Inventory
		IF NEW.inventory IS NULL THEN 
			NEW.inventory := (SELECT "value" FROM config_param_system WHERE "parameter"='edit_inventory_sysvdefault');
		END IF;

		--Publish
		IF NEW.publish IS NULL THEN 
			NEW.publish := (SELECT "value" FROM config_param_system WHERE "parameter"='edit_publish_sysvdefault');	
		END IF;

		SELECT code_autofill INTO v_code_autofill_bool FROM cat_feature JOIN cat_arc ON cat_feature.id=cat_arc.arctype_id WHERE cat_arc.id=NEW.arccat_id;
	
		--Copy id to code field	
		IF (v_code_autofill_bool IS TRUE) AND NEW.code IS NULL THEN 
			NEW.code=NEW.arc_id;
		END IF;

		-- Workcat_id
		IF (NEW.workcat_id IS NULL) THEN
			NEW.workcat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_workcat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- Ownercat_id
		IF (NEW.ownercat_id IS NULL) THEN
		    NEW.ownercat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_ownercat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
		
		-- Soilcat_id
		IF (NEW.soilcat_id IS NULL) THEN
			NEW.soilcat_id := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_soilcat_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;

		-- Builtdate
		IF (NEW.builtdate IS NULL) THEN
			NEW.builtdate :=(SELECT "value" FROM config_param_user WHERE "parameter"='edit_builtdate_vdefault' AND "cur_user"="current_user"() LIMIT 1);
			IF (NEW.builtdate IS NULL) AND (SELECT value::boolean FROM config_param_system WHERE parameter='edit_feature_auto_builtdate') IS TRUE THEN
				NEW.builtdate :=date(now());
			END IF;
		END IF;
		
		-- Verified
		IF (NEW.verified IS NULL) THEN
			NEW.verified := (SELECT "value" FROM config_param_user WHERE "parameter"='edit_verified_vdefault' AND "cur_user"="current_user"() LIMIT 1);
		END IF;
	
		-- LINK
		IF (SELECT "value" FROM config_param_system WHERE "parameter"='edit_feature_usefid_on_linkid')::boolean=TRUE THEN
			NEW.link=NEW.arc_id;
		END IF;
		
		v_featurecat = (SELECT arctype_id FROM cat_arc WHERE id = NEW.arccat_id);

		--Location type
		IF NEW.location_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_location_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.location_type = (SELECT value FROM config_param_user WHERE parameter = 'featureval_location_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.location_type IS NULL THEN
			NEW.location_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_arc_location_vdefault' AND cur_user = current_user);
		END IF;

		--Fluid type
		IF NEW.fluid_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_fluid_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.fluid_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_fluid_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.fluid_type IS NULL THEN
			NEW.fluid_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_arc_fluid_vdefault' AND cur_user = current_user);
		END IF;

		--Category type
		IF NEW.category_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_category_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.category_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_category_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.category_type IS NULL THEN
			NEW.category_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_arc_category_vdefault' AND cur_user = current_user);
		END IF;	

		--Function type
		IF NEW.function_type IS NULL AND (SELECT value FROM config_param_user WHERE parameter = 'edit_feature_function_vdefault' AND cur_user = current_user)  = v_featurecat THEN
			NEW.function_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_featureval_function_vdefault' AND cur_user = current_user);
		END IF;

		IF NEW.function_type IS NULL THEN
			NEW.function_type = (SELECT value FROM config_param_user WHERE parameter = 'edit_arc_function_vdefault' AND cur_user = current_user);
		END IF;
        
		--Pavement
		IF NEW.pavcat_id IS NULL THEN
			NEW.pavcat_id = (SELECT value FROM config_param_user WHERE parameter = 'edit_pavementcat_vdefault' AND cur_user = current_user);
		END IF;

		-- FEATURE INSERT
		INSERT INTO arc (arc_id, code, arccat_id, epa_type, sector_id, "state", state_type, annotation, observ,"comment",custom_length,dma_id, presszone_id, soilcat_id, function_type, category_type, fluid_type, location_type,
					workcat_id, workcat_id_end, workcat_id_plan, buildercat_id, builtdate,enddate, ownercat_id, muni_id, postcode, district_id, streetaxis_id, postnumber, postcomplement,
					streetaxis2_id,postnumber2, postcomplement2,descript,link,verified,the_geom,undelete,label_x,label_y,label_rotation,  publish, inventory, expl_id, num_value, 
					depth, adate, adescript, lastupdate, lastupdate_user, asset_id, pavcat_id)
					VALUES (NEW.arc_id, NEW.code, NEW.arccat_id, NEW.epa_type, NEW.sector_id, NEW."state", NEW.state_type, NEW.annotation, NEW.observ, NEW.comment, NEW.custom_length,NEW.dma_id,NEW. presszone_id,
					NEW.soilcat_id, NEW.function_type, NEW.category_type, NEW.fluid_type, NEW.location_type, NEW.workcat_id, NEW.workcat_id_end, NEW.workcat_id_plan, NEW.buildercat_id, NEW.builtdate,NEW.enddate, NEW.ownercat_id,
					NEW.muni_id, NEW.postcode, NEW.district_id,v_streetaxis,NEW.postnumber, NEW.postcomplement, v_streetaxis2, NEW.postnumber2, NEW.postcomplement2, NEW.descript,NEW.link, NEW.verified, 
					NEW.the_geom,NEW.undelete,NEW.label_x,NEW.label_y,NEW.label_rotation, NEW.publish, NEW.inventory, NEW.expl_id, NEW.num_value,
					NEW.depth, NEW.adate, NEW.adescript, NEW.lastupdate, NEW.lastupdate_user, NEW.asset_id, NEW.pavcat_id);

		-- this overwrites triger topocontrol arc values (triggered before insertion) just in that moment: In order to make more profilactic this issue only will be overwrited in case of NEW.node_* not nulls
		IF v_edit_enable_arc_nodes_update IS TRUE THEN
			IF NEW.node_1 IS NOT NULL THEN
				UPDATE arc SET node_1=NEW.node_1 WHERE arc_id=NEW.arc_id;
			END IF;
			IF NEW.node_2 IS NOT NULL THEN
				UPDATE arc SET node_2=NEW.node_2 WHERE arc_id=NEW.arc_id;
			END IF;
		END IF;

					
		-- MAN INSERT
		IF v_man_table='man_pipe' THEN 			
				INSERT INTO man_pipe (arc_id) VALUES (NEW.arc_id);			
			
		ELSIF v_man_table='man_varc' THEN		
				INSERT INTO man_varc (arc_id) VALUES (NEW.arc_id);

		ELSIF v_man_table='parent' THEN
			v_man_table := (SELECT man_table FROM cat_feature_arc c	JOIN sys_feature_cat s ON c.type = s.id 
			JOIN cat_arc ON c.id = cat_arc.arctype_id WHERE cat_arc.id=NEW.arccat_id);
        	IF v_man_table IS NOT NULL THEN
            	v_sql:= 'INSERT INTO '||v_man_table||' (arc_id) VALUES ('||quote_literal(NEW.arc_id)||')';    
           		EXECUTE v_sql;
      		END IF;		
		END IF;

		-- man addfields insert
		IF v_customfeature IS NOT NULL THEN
			FOR v_addfields IN SELECT * FROM sys_addfields
			WHERE (cat_feature_id = v_customfeature OR cat_feature_id is null) AND active IS TRUE AND iseditable IS TRUE
			LOOP
				EXECUTE 'SELECT $1."' || v_addfields.param_name||'"'
					USING NEW
					INTO v_new_value_param;

				IF v_new_value_param IS NOT NULL THEN
					EXECUTE 'INSERT INTO man_addfields_value (feature_id, parameter_id, value_param) VALUES ($1, $2, $3)'
						USING NEW.arc_id, v_addfields.id, v_new_value_param;
				END IF;	
			END LOOP;
		END IF;		

        -- EPA INSERT
        IF (NEW.epa_type = 'PIPE') THEN 
            v_inp_table:= 'inp_pipe';
		ELSIF (NEW.epa_type = 'VIRTUAL') THEN 
			v_inp_table:= 'inp_virtual';
        END IF;
		
		v_sql:= 'INSERT INTO '||v_inp_table||' (arc_id) VALUES ('||quote_literal(NEW.arc_id)||')';
        EXECUTE v_sql;
		
		--in case a project is dhc, insert cable
		IF (SELECT value FROM config_param_system WHERE parameter='dhc_plugin_version') is not null then
			IF (SELECT value::boolean FROM config_param_user WHERE parameter='dhc_edit_insert_cable' 
			AND cur_user=current_user) is true AND (SELECT json_extract_path_text(value::json,'cableFeaturecat')
				FROM config_param_system WHERE parameter='dhc_edit_insert_cable') != NEW.arc_type THEN
					raise notice 'execute';
					EXECUTE 'SELECT dhc_fct_edit_cable($${"client":{"device":4, "infoType":1, "lang":"ES"},
					"form":{},"feature":{"tableName":"v_edit_node", "featureType":"NODE", "id":[]}, 
					"data":{"filterFields":{}, "pageInfo":{},"arcId":"'||NEW.arc_id::text||'", 
					"arcGeom":"'||NEW.the_geom::text||'", "muniId":"'||NEW.muni_id::text||'", "explId":"'||NEW.expl_id::text||'",
					"state":"'||NEW.state::text||'","stateType":"'||NEW.state_type::text||'", "arcId":"'||NEW.arc_id||'" }}$$);';
			END IF;
		END IF;

        RETURN NEW;
    
    ELSIF TG_OP = 'UPDATE' THEN

    		-- this overwrites triger topocontrol arc values (triggered before insertion) just in that moment: In order to make more profilactic this issue only will be overwrited in case of NEW.node_* not nulls
		IF v_edit_enable_arc_nodes_update IS TRUE THEN
			IF NEW.node_1 IS NOT NULL THEN
				UPDATE arc SET node_1=NEW.node_1 WHERE arc_id=NEW.arc_id;
			END IF;
			IF NEW.node_2 IS NOT NULL THEN
				UPDATE arc SET node_2=NEW.node_2 WHERE arc_id=NEW.arc_id;
			END IF;
		END IF;

		-- epa type
		IF (NEW.epa_type != OLD.epa_type) THEN    

			-- delete from old inp table
			IF (OLD.epa_type = 'PIPE') THEN
				v_inp_table:= 'inp_pipe';
			ELSIF (OLD.epa_type = 'VIRTUALVALVE') THEN
				v_inp_table:= 'inp_virtualvalve';
			END IF;
			IF v_inp_table IS NOT NULL THEN
				v_sql:= 'DELETE FROM '||v_inp_table||' WHERE arc_id = '||quote_literal(OLD.arc_id);
				EXECUTE v_sql;
			END IF;
			
			v_inp_table := NULL;

			-- insert into new inp table
			IF (NEW.epa_type = 'PIPE') THEN
				INSERT INTO inp_pipe VALUES (NEW.arc_id) ON CONFLICT (arc_id) DO NOTHING;
			ELSIF (NEW.epa_type = 'VIRTUALVALVE') THEN
				INSERT INTO inp_virtualvalve (arc_id, status, valv_type) VALUES (NEW.arc_id, 'ACTIVE', 'FCV') ON CONFLICT (arc_id) DO NOTHING;
			END IF;
		END IF;
	
		-- State
		IF (NEW.state != OLD.state) THEN
			UPDATE arc SET state=NEW.state WHERE arc_id = OLD.arc_id;
			IF NEW.state = 2 AND OLD.state=1 THEN
				INSERT INTO plan_psector_x_arc (arc_id, psector_id, state, doable)
				VALUES (NEW.arc_id, (SELECT config_param_user.value::integer AS value FROM config_param_user WHERE config_param_user.parameter::text
				= 'plan_psector_vdefault'::text AND config_param_user.cur_user::name = "current_user"() LIMIT 1), 1, true);
			END IF;
			IF NEW.state = 1 AND OLD.state=2 THEN
				DELETE FROM plan_psector_x_arc WHERE arc_id=NEW.arc_id;					
			END IF;			
			IF NEW.state=0 THEN
				UPDATE arc SET node_1=NULL, node_2=NULL WHERE arc_id = OLD.arc_id;
			END IF;
		END IF;
		
		-- State_type
		IF NEW.state=0 AND OLD.state=1 THEN
			IF (SELECT state FROM value_state_type WHERE id=NEW.state_type) != NEW.state THEN
			NEW.state_type=(SELECT "value" FROM config_param_user WHERE parameter='statetype_end_vdefault' AND "cur_user"="current_user"() LIMIT 1);
				IF NEW.state_type IS NULL THEN
				NEW.state_type=(SELECT id from value_state_type WHERE state=0 LIMIT 1);
					IF NEW.state_type IS NULL THEN
					EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
					"data":{"message":"2110", "function":"1318","debug_msg":null}}$$);';

					END IF;
				END IF;
			END IF;
		END IF;

		--check relation state - state_type
		IF (NEW.state_type != OLD.state_type) AND NEW.state_type NOT IN (SELECT id FROM value_state_type WHERE state = NEW.state) THEN
			EXECUTE 'SELECT gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},
				"data":{"message":"3036", "function":"1318","debug_msg":"'||NEW.state::text||'"}}$$);';
		END IF;	
       			
		-- The geom
		IF st_orderingequals(NEW.the_geom, OLD.the_geom) IS FALSE OR NEW.node_1 IS NULL OR NEW.node_2 IS NULL THEN
			UPDATE arc SET the_geom=NEW.the_geom WHERE arc_id = OLD.arc_id;
		END IF;

		--link_path
		SELECT link_path INTO v_link_path FROM cat_feature JOIN cat_arc ON cat_arc.arctype_id=cat_feature.id WHERE cat_arc.id=NEW.arccat_id;
		
		IF v_link_path IS NOT NULL THEN
			NEW.link = replace(NEW.link, v_link_path,'');
		END IF;

		 -- Arc type for parent view
		IF v_man_table='parent' THEN
	    	IF (NEW.arccat_id != OLD.arccat_id) THEN
				v_new_arc_type= (SELECT system_id FROM cat_feature JOIN cat_arc ON cat_feature.id=arctype_id where cat_arc.id=NEW.arccat_id);
				v_old_arc_type= (SELECT system_id FROM cat_feature JOIN cat_arc ON cat_feature.id=arctype_id where cat_arc.id=OLD.arccat_id);
				IF v_new_arc_type != v_old_arc_type THEN
					v_sql='INSERT INTO man_'||lower(v_new_arc_type)||' (arc_id) VALUES ('||NEW.arc_id||')';
					EXECUTE v_sql;
					v_sql='DELETE FROM man_'||lower(v_old_arc_type)||' WHERE arc_id='||quote_literal(OLD.arc_id);
					EXECUTE v_sql;
				END IF;
			END IF;
		END IF;

		UPDATE arc
		SET code=NEW.code, arccat_id=NEW.arccat_id, epa_type=NEW.epa_type, sector_id=NEW.sector_id,  state_type=NEW.state_type, annotation= NEW.annotation, "observ"=NEW.observ, 
				"comment"=NEW.comment, custom_length=NEW.custom_length, dma_id=NEW.dma_id, presszone_id=NEW.presszone_id, soilcat_id=NEW.soilcat_id, function_type=NEW.function_type,
				category_type=NEW.category_type, fluid_type=NEW.fluid_type, location_type=NEW.location_type, workcat_id=NEW.workcat_id, workcat_id_end=NEW.workcat_id_end, workcat_id_plan=NEW.workcat_id_plan,
				buildercat_id=NEW.buildercat_id, builtdate=NEW.builtdate, enddate=NEW.enddate, ownercat_id=NEW.ownercat_id, muni_id=NEW.muni_id, streetaxis_id=v_streetaxis, 
				streetaxis2_id=v_streetaxis2,postcode=NEW.postcode, district_id = NEW.district_id, postnumber=NEW.postnumber, postnumber2=NEW.postnumber2,descript=NEW.descript, verified=NEW.verified, 
				undelete=NEW.undelete, label_x=NEW.label_x,
				postcomplement=NEW.postcomplement, postcomplement2=NEW.postcomplement2,label_y=NEW.label_y,label_rotation=NEW.label_rotation, publish=NEW.publish, inventory=NEW.inventory, 
				expl_id=NEW.expl_id,num_value=NEW.num_value, link=NEW.link, lastupdate=now(), lastupdate_user=current_user,
				depth=NEW.depth, adate=NEW.adate, adescript=NEW.adescript, asset_id=NEW.asset_id, pavcat_id=NEW.pavcat_id
				WHERE arc_id=OLD.arc_id;


		-- man addfields update
		IF v_customfeature IS NOT NULL THEN
			FOR v_addfields IN SELECT * FROM sys_addfields
			WHERE (cat_feature_id = v_customfeature OR cat_feature_id is null) AND active IS TRUE AND iseditable IS TRUE
			LOOP

			EXECUTE 'SELECT $1."' || v_addfields.param_name||'"'
				USING NEW
				INTO v_new_value_param;
 
			EXECUTE 'SELECT $1."' || v_addfields.param_name||'"'
				USING OLD
				INTO v_old_value_param;

			IF v_new_value_param IS NOT NULL THEN 

				EXECUTE 'INSERT INTO man_addfields_value(feature_id, parameter_id, value_param) VALUES ($1, $2, $3) 
					ON CONFLICT (feature_id, parameter_id)
					DO UPDATE SET value_param=$3 WHERE man_addfields_value.feature_id=$1 AND man_addfields_value.parameter_id=$2'
					USING NEW.arc_id , v_addfields.id, v_new_value_param;	

			ELSIF v_new_value_param IS NULL AND v_old_value_param IS NOT NULL THEN

				EXECUTE 'DELETE FROM man_addfields_value WHERE feature_id=$1 AND parameter_id=$2'
					USING NEW.arc_id , v_addfields.id;
			END IF;
		END LOOP;

        END IF;       
		--update values of related connecs;
		IF NEW.fluid_type != OLD.fluid_type AND v_autoupdate_fluid IS TRUE THEN
			UPDATE connec SET fluid_type = NEW.fluid_type WHERE arc_id = NEW.arc_id;
		END IF;

		RETURN NEW;

	ELSIF TG_OP = 'DELETE' THEN 
		
		EXECUTE 'SELECT gw_fct_getcheckdelete($${"client":{"device":4, "infoType":1, "lang":"ES"},
		"feature":{"id":"'||OLD.arc_id||'","featureType":"ARC"}, "data":{}}$$)';

		-- force plan_psector_force_delete
		SELECT value INTO v_force_delete FROM config_param_user WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;
		UPDATE config_param_user SET value = 'true' WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;
 
		DELETE FROM arc WHERE arc_id = OLD.arc_id;

		-- restore plan_psector_force_delete
		UPDATE config_param_user SET value = v_force_delete WHERE parameter = 'plan_psector_force_delete' and cur_user = current_user;
        
		--Delete addfields
  		DELETE FROM man_addfields_value WHERE feature_id = OLD.arc_id  and parameter_id in 
  		(SELECT id FROM sys_addfields WHERE cat_feature_id IS NULL OR cat_feature_id =OLD.arc_type);

		RETURN NULL;
	END IF;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
      