
/*==============================================================*
 | 03_CREATE_ADAE.SAS
 |
 | Purpose:
 |   Create an adverse event analysis dataset.
 |
 | Input:
 |   SDTM.AE
 |   ADAM.ADSL
 |
 | Output:
 |   ADAM.ADAE
 |
 | Important:
 |   TRTEMFL is a portfolio approximation. It identifies
 |   events with a known start date on or after first exposure.
 |   It does not implement a protocol-specific TEAE window or
 |   assess worsening of pre-existing events.
 *==============================================================*/

options validvarname=upcase;
options nodate nonumber;

%let root=/home/u64646326/clinical_trial_project;

libname sdtm "&root./data/source";
libname adam "&root./data/analysis";


/*--------------------------------------------------------------*
 | 1. Prepare ADSL treatment information
 *--------------------------------------------------------------*/

data work.adsl_ae;
    set adam.adsl;

    keep USUBJID
         TRT01P
         TRT01A
         TRTSDT
         TRTEDT
         SAFFL
         ITTFL;
run;


/*--------------------------------------------------------------*
 | 2. Convert AE dates and prepare source variables
 *--------------------------------------------------------------*/

data work.ae_prepared;
    set sdtm.ae;

    length AESTDT AEENDT 8;

    format AESTDT AEENDT date9.;

    /* Convert ISO 8601 date strings to SAS dates */
    if not missing(AESTDTC) then
        AESTDT=input(AESTDTC,yymmdd10.);

    if not missing(AEENDTC) then
        AEENDT=input(AEENDTC,yymmdd10.);

    /* Use preferred term when available */
    length AETERM_ANALYSIS $200;

    if not missing(AEDECOD) then
        AETERM_ANALYSIS=strip(AEDECOD);
    else
        AETERM_ANALYSIS=strip(AETERM);

    /* Use primary SOC when available */
    length AESOC_ANALYSIS $100;

    if not missing(AESOC) then
        AESOC_ANALYSIS=strip(AESOC);
    else
        AESOC_ANALYSIS=strip(AEBODSYS);

    label AESTDT="Adverse Event Start Date"
          AEENDT="Adverse Event End Date"
          AETERM_ANALYSIS="Analysis Preferred Term"
          AESOC_ANALYSIS="Analysis System Organ Class";
run;


/*--------------------------------------------------------------*
 | 3. Sort datasets before merging
 *--------------------------------------------------------------*/

proc sort data=work.ae_prepared
          out=work.ae_sorted;
    by USUBJID;
run;

proc sort data=work.adsl_ae
          out=work.adsl_ae_sorted;
    by USUBJID;
run;


/*--------------------------------------------------------------*
 | 4. Merge AE and subject-level treatment information
 *--------------------------------------------------------------*/

data adam.adae;

    merge work.ae_sorted(in=IN_AE)
          work.adsl_ae_sorted(in=IN_ADSL);

    by USUBJID;

    /* Retain all source AE records */
    if IN_AE;

    length TRTEMFL $1
           AETOXGR $8;

    /* Portfolio treatment-emergent approximation */
    if not IN_ADSL then TRTEMFL="";
    else if missing(AESTDT) or missing(TRTSDT) then TRTEMFL="";
    else if AESTDT >= TRTSDT then TRTEMFL="Y";
    else TRTEMFL="N";

    /* Preserve severity as the available toxicity-grade proxy */
    AETOXGR=strip(AESEV);

    format TRTSDT TRTEDT AESTDT AEENDT date9.;

    label TRTEMFL="Provisional Treatment-Emergent Flag"
          AETOXGR="Adverse Event Severity"
          TRT01P="Planned Treatment"
          TRT01A="Actual Treatment"
          SAFFL="Safety Population Flag"
          ITTFL="Provisional ITT Population Flag";
run;


/*--------------------------------------------------------------*
 | 5. Inspect ADAE structure
 *--------------------------------------------------------------*/

title "ADAE Dataset Structure";

proc contents data=adam.adae varnum;
run;


/*--------------------------------------------------------------*
 | 6. Check record counts and key variables
 *--------------------------------------------------------------*/

title "ADAE Record Count and Treatment-Emergent Summary";

proc sql;

    select count(*) as TOTAL_AE_RECORDS,
           count(distinct USUBJID) as SUBJECTS_WITH_AE,
           sum(TRTEMFL="Y") as PROVISIONAL_TEAE_RECORDS,
           sum(TRTEMFL="N") as NON_TEAE_RECORDS,
           sum(missing(TRTEMFL)) as UNCLASSIFIED_RECORDS,
           sum(AESER="Y") as SERIOUS_AE_RECORDS
    from adam.adae;

quit;


/*--------------------------------------------------------------*
 | 7. AE records by treatment and severity
 *--------------------------------------------------------------*/

title "AE Records by Actual Treatment and Severity";

proc freq data=adam.adae;
    tables TRT01A*AESEV / missing;
run;


/*--------------------------------------------------------------*
 | 8. AE records by SOC
 *--------------------------------------------------------------*/

title "AE Records by System Organ Class";

proc freq data=adam.adae;
    tables AESOC_ANALYSIS / missing;
run;


/*--------------------------------------------------------------*
 | 9. Check for duplicate AE keys
 *--------------------------------------------------------------*/

proc sort data=adam.adae
          out=work.adae_unique
          nodupkey
          dupout=work.adae_duplicates;

    by USUBJID AESEQ;

run;

title "ADAE Duplicate Key Check";

proc sql;
    select count(*) as DUPLICATE_AE_KEYS
    from work.adae_duplicates;
quit;


/*--------------------------------------------------------------*
 | 10. Check date conversion
 *--------------------------------------------------------------*/

title "ADAE Date Conversion Checks";

proc sql;

    select count(*) as TOTAL_RECORDS,
           sum(missing(AESTDTC)) as MISSING_SOURCE_START_DATE,
           sum(not missing(AESTDTC) and missing(AESTDT))
               as UNCONVERTED_START_DATE,
           sum(missing(AEENDTC)) as MISSING_SOURCE_END_DATE,
           sum(not missing(AEENDTC) and missing(AEENDT))
               as UNCONVERTED_END_DATE
    from adam.adae;

quit;


/*--------------------------------------------------------------*
 | 11. Check unmatched AE subjects
 *--------------------------------------------------------------*/

title "AE Subjects Without ADSL Treatment Information";

proc sql;

    select count(distinct A.USUBJID) as UNMATCHED_AE_SUBJECTS

    from work.ae_sorted as A

    left join work.adsl_ae_sorted as B
        on A.USUBJID=B.USUBJID

    where missing(B.USUBJID);

quit;

title;
