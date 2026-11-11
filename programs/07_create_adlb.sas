
/*==============================================================*
 | 07_CREATE_ADLB.SAS
 | Purpose: Create laboratory analysis dataset (ADLB)
 | Source:  SDTM.LB and ADAM.ADSL
 | Output:  ADAM.ADLB
 *==============================================================*/

%let project=/home/u64646326/clinical_trial_project;

libname sdtm "&project./data/source";
libname adam "&project./data/analysis";

/*--------------------------------------------------------------*
 | STEP 1: Clear previous WORK datasets
 *--------------------------------------------------------------*/

proc datasets library=work nolist;
    delete adlb_source
           adlb_base
           adlb
           adlb_qc
           adlb_duplicate_check
           adlb_baseline_qc
           adlb_population_qc;
quit;


/*--------------------------------------------------------------*
 | STEP 2: Prepare laboratory records and merge treatment data
 *--------------------------------------------------------------*/

proc sort data=sdtm.lb out=work.adlb_source;
    by USUBJID LBSEQ;
run;

proc sort data=adam.adsl out=work.adlb_base;
    by USUBJID;
run;

data work.adlb;
    merge work.adlb_source(in=inlb)
          work.adlb_base(
              keep=USUBJID TRT01A TRTSDT TRTEDT SAFFL
          );
    by USUBJID;

    if inlb;

    length PARAMCD $8
           PARAM $100
           ANRIND $20
           ABLFL $1
           BASETYPE $20
           DTYPE $20;

    /* Analysis date */

    if not missing(LBDTC) then
        ADT=input(substr(strip(LBDTC),1,10),yymmdd10.);
    else ADT=.;

    format ADT date9.;

    /* Analysis parameter and result */

    PARAMCD=strip(LBTESTCD);
    PARAM=strip(LBTEST);
    AVAL=LBSTRESN;

    /* Reference range */

    ANRLO=LBSTNRLO;
    ANRHI=LBSTNRHI;
    ANRIND=strip(LBNRIND);

    /* Treatment-emergent study day */

    if not missing(ADT) and not missing(TRTSDT) then do;
        if ADT >= TRTSDT then
            ADY=ADT-TRTSDT+1;
        else
            ADY=ADT-TRTSDT;
    end;
    else ADY=.;

    /* Preserve source baseline flag */

    if upcase(strip(LBBLFL))="Y" then
        ABLFL="Y";
    else
        ABLFL="";

    BASETYPE="SOURCE LBBLFL";

    /* Baseline value */

    BASE=.;

    /* Change from baseline */

    CHG=.;

    /* Percent change from baseline */

    PCHG=.;

    /* Analysis record type */

    if not missing(ADT) and not missing(TRTSDT) then do;
        if ADT >= TRTSDT then
            DTYPE="POST-BASELINE";
        else
            DTYPE="PRE-BASELINE";
    end;
    else DTYPE="UNCLASSIFIED";

    label
        ADT="Analysis Date"
        ADY="Analysis Relative Study Day"
        PARAMCD="Analysis Parameter Code"
        PARAM="Analysis Parameter"
        AVAL="Analysis Value"
        ANRLO="Analysis Normal Range Low"
        ANRHI="Analysis Normal Range High"
        ANRIND="Analysis Reference Range Indicator"
        ABLFL="Baseline Record Flag"
        BASE="Baseline Value"
        CHG="Change from Baseline"
        PCHG="Percent Change from Baseline"
        DTYPE="Analysis Record Type"
        BASETYPE="Baseline Definition";

run;


/*--------------------------------------------------------------*
 | STEP 3: Derive baseline values by subject and parameter
 |
 | Use records explicitly marked LBBLFL=Y.
 | If multiple source baseline records exist for a subject and
 | parameter, select the record with the earliest LBSEQ.
 *--------------------------------------------------------------*/

proc sort data=work.adlb;
    by USUBJID PARAMCD LBSEQ;
run;

data work.adlb_baseline_values;
    set work.adlb;
    where ABLFL="Y" and not missing(AVAL);

    by USUBJID PARAMCD;

    if first.PARAMCD;

    BASE=AVAL;

    keep USUBJID PARAMCD BASE;
run;


/*--------------------------------------------------------------*
 | STEP 4: Attach baseline values and calculate CHG/PCHG
 *--------------------------------------------------------------*/

proc sort data=work.adlb;
    by USUBJID PARAMCD;
run;

proc sort data=work.adlb_baseline_values;
    by USUBJID PARAMCD;
run;

data work.adlb;
    merge work.adlb(in=a)
          work.adlb_baseline_values;
    by USUBJID PARAMCD;

    if a;

    if not missing(BASE) and not missing(AVAL) then do;
        CHG=AVAL-BASE;

        if BASE ne 0 then
            PCHG=(CHG/BASE)*100;
        else
            PCHG=.;
    end;

    format BASE AVAL CHG 12.3
           PCHG 12.2;

run;


/*--------------------------------------------------------------*
 | STEP 5: Baseline and post-baseline flags
 *--------------------------------------------------------------*/

data work.adlb;
    set work.adlb;

    length ANL01FL $1;

    if ABLFL="Y" then ANL01FL="Y";
    else if not missing(ADT) and not missing(TRTSDT)
         and ADT >= TRTSDT then ANL01FL="Y";
    else ANL01FL="";

    label ANL01FL="Primary Analysis Record Flag";

run;


/*--------------------------------------------------------------*
 | STEP 6: Save permanent ADLB dataset
 *--------------------------------------------------------------*/

data adam.adlb;
    set work.adlb;
run;


/*--------------------------------------------------------------*
 | STEP 7: Dataset structure
 *--------------------------------------------------------------*/

title "ADLB Dataset Structure";

proc contents data=adam.adlb varnum;
run;


/*--------------------------------------------------------------*
 | STEP 8: Laboratory record counts by treatment
 *--------------------------------------------------------------*/

title "Laboratory Records by Treatment";

proc sql;

    select
        TRT01A,
        count(*) as LAB_RECORDS,
        count(distinct USUBJID) as SUBJECTS,
        sum(case when ABLFL="Y" then 1 else 0 end)
            as BASELINE_RECORDS,
        sum(case when DTYPE="POST-BASELINE" then 1 else 0 end)
            as POST_BASELINE_RECORDS

    from adam.adlb

    group by TRT01A
    order by TRT01A;

quit;


/*--------------------------------------------------------------*
 | STEP 9: Baseline flag reconciliation
 *--------------------------------------------------------------*/

title "QC: Source and Derived Baseline Flags";

proc freq data=adam.adlb;
    tables LBBLFL*ABLFL / missing norow nocol;
run;


/*--------------------------------------------------------------*
 | STEP 10: Duplicate laboratory record check
 *--------------------------------------------------------------*/

proc sql;

    create table work.adlb_duplicate_check as

    select
        USUBJID,
        LBSEQ,
        count(*) as RECORD_COUNT

    from adam.adlb

    group by USUBJID, LBSEQ

    having count(*) > 1;

    title "QC: Duplicate Laboratory Records";

    select count(*) as DUPLICATE_RECORD_KEYS
    from work.adlb_duplicate_check;

quit;


/*--------------------------------------------------------------*
 | STEP 11: Check baseline uniqueness per subject and parameter
 *--------------------------------------------------------------*/

proc sql;

    create table work.adlb_baseline_qc as

    select
        USUBJID,
        PARAMCD,
        sum(case when ABLFL="Y" then 1 else 0 end)
            as BASELINE_RECORDS

    from adam.adlb

    group by USUBJID, PARAMCD

    having calculated BASELINE_RECORDS > 1;

    title "QC: Multiple Source Baseline Records per Subject/Parameter";

    select count(*) as MULTIPLE_BASELINE_KEYS
    from work.adlb_baseline_qc;

quit;


/*--------------------------------------------------------------*
 | STEP 12: Check baseline and change derivations
 *--------------------------------------------------------------*/

proc sql;

    create table work.adlb_qc as

    select
        count(*) as TOTAL_RECORDS,

        sum(case
            when ABLFL="Y" and missing(BASE)
            then 1 else 0
        end) as BASELINE_WITHOUT_BASE,

        sum(case
            when not missing(CHG) and
                 abs(CHG-(AVAL-BASE)) > 0.000001
            then 1 else 0
        end) as CHG_CALCULATION_ERRORS,

        sum(case
            when not missing(PCHG) and
                 (missing(BASE) or BASE=0)
            then 1 else 0
        end) as INVALID_PERCENT_CHANGE,

        sum(case
            when missing(USUBJID)
            then 1 else 0
        end) as MISSING_SUBJECT_IDS,

        sum(case
            when missing(PARAMCD)
            then 1 else 0
        end) as MISSING_PARAMETER_CODES,

        sum(case
            when missing(AVAL)
            then 1 else 0
        end) as MISSING_ANALYSIS_VALUES

    from adam.adlb;

quit;

title "QC: ADLB Derivation Checks";

proc print data=work.adlb_qc noobs;
run;


/*--------------------------------------------------------------*
 | STEP 13: Check subject linkage to ADSL
 *--------------------------------------------------------------*/

proc sql;

    create table work.adlb_population_qc as

    select
        count(*) as TOTAL_LAB_RECORDS,

        sum(case
            when missing(b.USUBJID)
            then 1 else 0
        end) as UNMATCHED_RECORDS

    from sdtm.lb as a

    left join adam.adsl as b
        on a.USUBJID=b.USUBJID;

quit;

title "QC: Laboratory Subject Linkage";

proc print data=work.adlb_population_qc noobs;
run;


/*--------------------------------------------------------------*
 | STEP 14: Summary of laboratory parameters
 *--------------------------------------------------------------*/

title "Laboratory Parameter Summary";

proc sql;

    select
        PARAMCD,
        PARAM,
        count(*) as RECORDS,
        count(distinct USUBJID) as SUBJECTS,
        sum(case when ABLFL="Y" then 1 else 0 end)
            as BASELINE_RECORDS

    from adam.adlb

    group by PARAMCD, PARAM

    order by PARAMCD;

quit;


/*--------------------------------------------------------------*
 | STEP 15: Completion
 *--------------------------------------------------------------*/

%put NOTE: ADLB creation completed.;
%put NOTE: Review baseline reconciliation and all QC outputs.;

title;
