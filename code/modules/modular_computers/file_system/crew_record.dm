GLOBAL_LIST_EMPTY(all_crew_records)
GLOBAL_LIST_INIT(blood_types, list("A-", "A+", "B-", "B+", "AB-", "AB+", "O-", "O+"))
GLOBAL_LIST_INIT(physical_statuses, list("Active", "Disabled", "SSD", "Deceased"))
GLOBAL_VAR_INIT(default_physical_status, "Active")
GLOBAL_LIST_INIT(security_statuses, list("None", "Released", "Parolled", "Incarcerated", "Arrest"))
GLOBAL_VAR_INIT(default_security_status, "None")
GLOBAL_VAR_INIT(arrest_security_status, "Arrest")
#define GETTER_SETTER(KEY) /datum/computer_file/crew_record/proc/get_##KEY(){var/record_field/F = locate(/record_field/##KEY) in fields; if(F) return F.get_value()} \
/datum/computer_file/crew_record/proc/set_##KEY(value){var/record_field/F = locate(/record_field/##KEY) in fields; if(F) return F.set_value(value)}

// Fear not the preprocessor, for it is a friend. To add a field, use one of these, depending on value type and if you need special access to see it.
// It will also create getter/setter procs for record datum, named like /get_[key here]() /set_[key_here](value) e.g. get_name() set_name(value)
// Use getter setters to avoid errors caused by typoing the string key.
#define FIELD_SHORT(NAME, KEY) /record_field/##KEY/name = ##NAME; GETTER_SETTER(##KEY)
#define FIELD_SHORT_SECURE(NAME, KEY, ACCESS) FIELD_SHORT(##NAME, ##KEY); /record_field/##KEY/acccess = ##ACCESS

#define FIELD_LONG(NAME, KEY) FIELD_SHORT(##NAME, ##KEY); /record_field/##KEY/valtype = EDIT_LONGTEXT
#define FIELD_LONG_SECURE(NAME, KEY, ACCESS) FIELD_LONG(##NAME, ##KEY); /record_field/##KEY/acccess = ##ACCESS

#define FIELD_NUM(NAME, KEY) FIELD_SHORT(##NAME, ##KEY); /record_field/##KEY/valtype = EDIT_NUMERIC; /record_field/##KEY/value = 0
#define FIELD_NUM_SECURE(NAME, KEY, ACCESS) FIELD_NUM(##NAME, ##KEY); /record_field/##KEY/acccess = ##ACCESS

#define FIELD_LIST(NAME, KEY, OPTIONS) FIELD_SHORT(##NAME, ##KEY); /record_field/##KEY/valtype = EDIT_LIST; /record_field/##KEY/get_options(){. = ##OPTIONS;}
#define FIELD_LIST_SECURE(NAME, KEY, OPTIONS, ACCESS) FIELD_LIST(##NAME, ##KEY, ##OPTIONS); /record_field/##KEY/acccess = ##ACCESS

// GENERIC RECORDS
FIELD_SHORT("Name",name)
FIELD_SHORT("Job",job)
FIELD_LIST("Sex", sex, record_genders())
FIELD_NUM("Age", age)

FIELD_LIST("Status", status, GLOB.physical_statuses)
/record_field/status/acccess_edit = access_medical

FIELD_SHORT("Species",species)
FIELD_LIST("Branch", branch, record_branches())
FIELD_LIST("Rank", rank, record_ranks())

// MEDICAL RECORDS
FIELD_LIST("Blood Type", bloodtype, GLOB.blood_types)
FIELD_LONG_SECURE("Medical Record", medRecord, access_medical)

// SECURITY RECORDS
FIELD_LIST_SECURE("Criminal Status", criminalStatus, GLOB.security_statuses, access_security)
FIELD_LONG_SECURE("Security Record", secRecord, access_security)
FIELD_SHORT_SECURE("DNA", dna, access_security)
FIELD_SHORT_SECURE("Fingerprint", fingerprint, access_security)

// EMPLOYMENT RECORDS
FIELD_LONG_SECURE("Employment Record", emplRecord, access_heads)
FIELD_SHORT_SECURE("Home System", homeSystem, access_heads)
FIELD_SHORT_SECURE("Citizenship", citizenship, access_heads)
FIELD_SHORT_SECURE("Faction", faction, access_heads)
FIELD_SHORT_SECURE("Religion", religion, access_heads)

// ANTAG RECORDS
FIELD_LONG_SECURE("Exploitable Information", antagRecord, access_syndicate)


// Kept as a computer file for possible future expansion into servers.
/datum/computer_file/crew_record
	filetype = "CDB"
	size = 2

	// String fields that can be held by this record.
	// Try to avoid manipulating the fields_ variables directly - use getters/setters below instead.
	var/icon/photo_front = null
	var/icon/photo_side = null
	var/list/fields = list()	// Fields of this record
	var/datum/money_account/linked_account
	var/list/access = list() // used for factional access
	var/suspended = 0
	var/terminated = 0
	var/assignment_uid
	var/list/promote_votes = list()
	var/list/demote_votes = list()
	var/rank = 0
	var/custom_title
	var/assignment_data = list() // format = list(assignment_uid = rank)
	var/validate_time = 0
	var/worked = 0
/datum/computer_file/crew_record/New()
	..()
	for(var/T in subtypesof(/record_field/))
		new T(src)
	load_from_mob(null)

/datum/computer_file/crew_record/Destroy()
	. = ..()
	GLOB.all_crew_records.Remove(src)
/datum/computer_file/crew_record/proc/try_duty()
	if(suspended > world.realtime || terminated)
		return 0
	else
		return assignment_uid
/datum/computer_file/crew_record/proc/check_rank_change(var/datum/world_faction/faction)
	var/list/all_promotes = list()
	var/list/three_promotes = list()
	var/list/five_promotes = list()
	var/list/all_demotes = list()
	var/list/three_demotes = list()
	var/list/five_demotes = list()
	var/datum/assignment/curr_assignment = faction.get_assignment(assignment_uid)
	if(!curr_assignment) return 0
	for(var/name in promote_votes)
		if(name == get_name()) continue
		var/datum/computer_file/crew_record/record = faction.get_record(name)
		if(record)
			var/head_position = 0
			var/datum/assignment/assignment = faction.get_assignment(record.assignment_uid)
			if(assignment)
				if(curr_assignment.parent)
					if(curr_assignment.parent.command_faction)
						if(curr_assignment.parent.head_position.uid == curr_assignment.uid) head_position = 1
				if(assignment.parent.command_faction || assignment.parent.name == curr_assignment.parent.name) // either the promotion is coming from a command position or its coming from an internal promotion request
					if(assignment.parent)
						if(assignment.parent.head_position.uid != assignment.uid && curr_assignment.parent.head_position.uid == curr_assignment.uid) // The promoted position is a head position and the promoter is not
							continue
						if((assignment.uid == curr_assignment.uid || assignment.parent.head_position.uid != assignment.uid) && record.rank <= rank) // they have the same assignment and we are equal or less rank
							continue
					if(assignment.accesses.Find("2"))
						if(record.rank >= 5 || (record.rank >= assignment.ranks.len && head_position))
							five_promotes |= name
						if(record.rank >= 3 || (record.rank >= assignment.ranks.len && head_position))
							three_promotes |= name
						all_promotes |= name
	if(five_promotes.len >= faction.five_promote_req)
		rank++
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
	if(three_promotes.len >= faction.three_promote_req)
		rank++
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
	if(all_promotes.len >= faction.all_promote_req)
		rank++
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
	for(var/name in demote_votes)
		var/datum/computer_file/crew_record/record = faction.get_record(name)
		if(record)
			var/head_position = 0
			var/datum/assignment/assignment = faction.get_assignment(record.assignment_uid)
			if(assignment)
				if(curr_assignment.parent)
					if(curr_assignment.parent.command_faction)
						if(curr_assignment.parent.head_position.uid == curr_assignment.uid) head_position = 1
				if(assignment.parent.head_position.uid != assignment.uid && curr_assignment.parent.head_position.uid == curr_assignment.uid) // The promoted position is a head position and the promoter is not
					message_admins("disregard 1")
					continue
				if((assignment.uid == curr_assignment.uid || assignment.parent.head_position.uid != assignment.uid) && record.rank <= rank) // they have the same assignment and we are equal or less rank
					message_admins("disregard 2")
					continue
				if(assignment.accesses.Find("2") || record.access.Find("2"))
					if(record.rank >= 5 || (record.rank >= assignment.ranks.len && head_position))
						five_demotes |= name
					if(record.rank >= 3 || (record.rank >= assignment.ranks.len && head_position))
						three_demotes |= name
					all_demotes |= name
	if(five_demotes.len >= faction.five_promote_req)
		rank--
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
	if(three_demotes.len >= faction.three_promote_req)
		rank--
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
	if(all_demotes.len >= faction.all_promote_req)
		rank--
		promote_votes.Cut()
		demote_votes.Cut()
		update_ids(get_name())
		return
/datum/computer_file/crew_record/proc/load_from_id(var/obj/item/weapon/card/id/card)
	if(!istype(card))
		return 0
	photo_front = card.front
	photo_side = card.side

	set_name(card.registered_name)
	set_job("Unset")
	set_sex(card.sex)
	set_age(card.age)
	set_status(GLOB.default_physical_status)
	set_species(card.species)
	// Medical record
	set_bloodtype(card.blood_type)
	set_medRecord("No record supplied")

	// Security record
	set_criminalStatus(GLOB.default_security_status)
	set_dna(card.dna_hash)
	set_fingerprint(card.fingerprint_hash)
	set_secRecord("No record supplied")

	// Employment record
	set_emplRecord("No record supplied")
	return 1
/datum/computer_file/crew_record/proc/load_from_global(var/real_name)
	var/datum/computer_file/crew_record/record
	for(var/datum/computer_file/crew_record/R in GLOB.all_crew_records)
		if(R.get_name() == real_name)
			record = R
			break
	if(!record)
		return 0
	photo_front = record.photo_front
	photo_side = record.photo_side
	set_name(record.get_name())
	set_job(record.get_job())
	set_sex(record.get_sex())
	set_age(record.get_age())
	set_status(record.get_status())
	set_species(record.get_species())

	// Medical record
	set_bloodtype(record.get_bloodtype())
	set_medRecord("No record supplied")

	// Security record
	set_criminalStatus(GLOB.default_security_status)
	set_dna(record.get_dna())
	set_fingerprint(record.get_fingerprint())
	set_secRecord("No record supplied")

	// Employment record
	set_emplRecord("No record supplied")
	set_homeSystem(record.get_homeSystem())
	set_religion(record.get_religion())
	return 1

/datum/computer_file/crew_record/proc/load_from_mob(var/mob/living/carbon/human/H)
	if(istype(H))
		if(H.mind && H.mind.initial_account)
			linked_account = H.mind.initial_account
		photo_front = getFlatIcon(H, SOUTH, always_use_defdir = 1)
		photo_side = getFlatIcon(H, WEST, always_use_defdir = 1)
	else
		var/mob/living/carbon/human/dummy = new()
		photo_front = getFlatIcon(dummy, SOUTH, always_use_defdir = 1)
		photo_side = getFlatIcon(dummy, WEST, always_use_defdir = 1)
		qdel(dummy)

	// Generic record
	set_name(H ? H.real_name : "Unset")
	set_job(H ? GetAssignment(H) : "Unset")
	set_sex(H ? gender2text(H.gender) : "Unset")
	set_age(H ? H.age : 30)
	set_status(GLOB.default_physical_status)
	set_species(H ? H.get_species() : SPECIES_HUMAN)
	set_branch(H ? (H.char_branch && H.char_branch.name) : "None")
	set_rank(H ? (H.char_rank && H.char_rank.name) : "None")

	// Medical record
	set_bloodtype(H ? H.b_type : "Unset")
	set_medRecord((H && H.med_record && !jobban_isbanned(H, "Records") ? html_decode(H.med_record) : "No record supplied"))

	// Security record
	set_criminalStatus(GLOB.default_security_status)
	set_dna(H ? H.dna.unique_enzymes : "")
	set_fingerprint(H ? md5(H.dna.uni_identity) : "")
	set_secRecord((H && H.sec_record && !jobban_isbanned(H, "Records") ? html_decode(H.sec_record) : "No record supplied"))

	// Employment record
	set_emplRecord((H && H.gen_record && !jobban_isbanned(H, "Records") ? html_decode(H.gen_record) : "No record supplied"))
	set_homeSystem(H ? H.home_system : "Unset")
	set_citizenship(H ? H.citizenship : "Unset")
	set_faction(H ? H.personal_faction : "Unset")
	set_religion(H ? H.religion : "Unset")

	// Antag record
	set_antagRecord((H && H.exploit_record && !jobban_isbanned(H, "Records") ? html_decode(H.exploit_record) : ""))

// Returns independent copy of this file.
/datum/computer_file/crew_record/clone(var/rename = 0)
	var/datum/computer_file/crew_record/temp = ..()
	return temp

/datum/computer_file/crew_record/proc/get_field(var/field_type)
	var/record_field/F = locate(field_type) in fields
	if(F)
		return F.get_value()

/datum/computer_file/crew_record/proc/set_field(var/field_type, var/value)
	var/record_field/F = locate(field_type) in fields
	if(F)
		return F.set_value(value)

// Global methods
// Used by character creation to create a record for new arrivals.
/proc/CreateModularRecord(var/mob/living/carbon/human/H)
	for(var/datum/computer_file/crew_record/R in GLOB.all_crew_records)
		if(R.get_name() == H.real_name)
			message_admins("record already found heh")
			return R
	var/datum/computer_file/crew_record/CR = new/datum/computer_file/crew_record()
	GLOB.all_crew_records.Add(CR)
	CR.load_from_mob(H)
	return CR

// Gets crew records filtered by set of positions
/proc/department_crew_manifest(var/list/filter_positions, var/blacklist = FALSE)
	var/list/matches = list()
	for(var/datum/computer_file/crew_record/CR in GLOB.all_crew_records)
		var/rank = CR.get_job()
		if(blacklist)
			if(!(rank in filter_positions))
				matches.Add(CR)
		else
			if(rank in filter_positions)
				matches.Add(CR)
	return matches

// Simple record to HTML (for paper purposes) conversion.
// Not visually that nice, but it gets the work done, feel free to tweak it visually
/proc/record_to_html(var/datum/computer_file/crew_record/CR, var/access)
	var/dat = "<tt><H2>RECORD DATABASE DATA DUMP</H2><i>Generated on: [stationdate2text()] [stationtime2text()]</i><br>******************************<br>"
	dat += "<table>"
	for(var/record_field/F in CR.fields)
		if(F.can_see(access))
			dat += "<tr><td><b>[F.name]</b>"
			if(F.valtype == EDIT_LONGTEXT)
				dat += "<tr>"
			dat += "<td>[F.get_display_value()]"
	dat += "</tt>"
	return dat

/proc/get_crewmember_record(var/name)
	for(var/datum/computer_file/crew_record/CR in GLOB.all_crew_records)
		if(CR.get_name() == name)
			return CR
	return null

/proc/GetAssignment(var/mob/living/carbon/human/H)
	if(!H)
		return "Unassigned"
	if(!H.mind)
		return H.job
	if(H.mind.role_alt_title)
		return H.mind.role_alt_title
	return H.mind.assigned_role

/record_field
	var/name = "Unknown"
	var/value = "Unset"
	var/valtype = EDIT_SHORTTEXT
	var/acccess
	var/acccess_edit
	var/record_id

/record_field/New(var/datum/computer_file/crew_record/record)
	if(!acccess_edit)
		acccess_edit = acccess ? acccess : access_heads
	if(record)
		record_id = record.uid
		record.fields += src
	..()

/record_field/proc/get_value()
	return value

/record_field/proc/get_display_value()
	if(valtype == EDIT_LONGTEXT)
		return pencode2html(value)
	return value

/record_field/proc/set_value(var/newval)
	if(isnull(newval))
		return
	switch(valtype)
		if(EDIT_LIST)
			var/options = get_options()
			if(!(newval in options))
				return
		if(EDIT_SHORTTEXT)
			newval = newval
		if(EDIT_LONGTEXT)
			newval = sanitize(replacetext(newval, "\n", "\[br\]"), MAX_PAPER_MESSAGE_LEN)
	value = newval
	return 1

/record_field/proc/get_options()
	return list()

/record_field/proc/can_edit(var/used_access)
	if(!acccess_edit)
		return TRUE
	if(!used_access)
		return FALSE
	return islist(used_access) ? (acccess_edit in used_access) : acccess_edit == used_access

/record_field/proc/can_see(var/used_access)
	if(!acccess)
		return TRUE
	if(!used_access)
		return FALSE
	return islist(used_access) ? (acccess_edit in used_access) : acccess_edit == used_access

//Options builderes
/record_field/rank/proc/record_ranks()
	for(var/datum/computer_file/crew_record/R in GLOB.all_crew_records)
		if(R.uid == record_id)
			var/datum/mil_branch/branch = mil_branches.get_branch(R.get_branch())
			if(!branch)
				return null
			. = list()
			. |= "Unset"
			for(var/rank in branch.ranks)
				var/datum/mil_rank/RA = branch.ranks[rank]
				. |= RA.name

/record_field/sex/proc/record_genders()
	. = list()
	. |= "Unset"
	for(var/G in gender_datums)
		. |= gender2text(G)

/record_field/branch/proc/record_branches()
	. = list()
	. |= "Unset"
	for(var/B in mil_branches.branches)
		var/datum/mil_branch/BR = mil_branches.branches[B]
		. |= BR.name