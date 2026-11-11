OPTIONS NONOTES NOSTIMER NOSOURCE NOSYNTAXCHECK;

/***************************************************************
  PROGRAM: 10_LAB_SHIFT.sas

  PURPOSE:
    Baseline-to-post-baseline laboratory status shift analysis
    by treatment and laboratory parameter.

  INPUT:
    ADAM.ADLB

  OUTPUT:
    OUTTAB.LAB_SHIFT
    OUTTAB.LAB_SHIFT_QC
    OUTTAB.LAB_SHIFT_RECON
****************************************************************/

/*--------------------------------------------------------------
  STEP 1: Extract baseline laboratory status
--------------------------------------------------------------*/

data work.lab_baseline;
    set adam.adlb;

    where SAFFL = "Y"
          and ABLFL = "Y"
          and not missing(USUBJID)
          and not missing(TRT01A)
          and not missing(PARAMCD);

    length BASE_STATUS $20;

    BASE_STATUS = upcase(strip(ANRIND));

    if BASE_STATUS not in ("LOW", "NORMAL", "HIGH") then
        BASE_STATUS = "UNKNOWN";

    keep USUBJID TRT01A PARAMCD PARAM BASE_STATUS;
run;


/*--------------------------------------------------------------
  STEP 2: Check baseline duplicates
--------------------------------------------------------------*/

proc sql;
    create table work.lab_baseline_duplicates as
    select
        USUBJID,
        PARAMCD,
        count(*) as RECORD_COUNT
    from work.lab_baseline
    group by USUBJID, PARAMCD
    having calculated RECORD_COUNT > 1;
quit;


/*--------------------------------------------------------------
  STEP 3: Extract post-baseline laboratory records
--------------------------------------------------------------*/

data work.lab_postbaseline;
    set adam.adlb;

    where SAFFL = "Y"
          and ADY > 0
          and not missing(AVAL)
          and not missing(USUBJID)
          and not missing(TRT01A)
          and not missing(PARAMCD);

    length POST_STATUS $20;

    POST_STATUS = upcase(strip(ANRIND));

    if POST_STATUS in ("LOW", "NORMAL", "HIGH");

    keep USUBJID TRT01A PARAMCD PARAM POST_STATUS;
run;


/*--------------------------------------------------------------
  STEP 4: Derive post-baseline status flags by subject/parameter
--------------------------------------------------------------*/

proc sql;
    create table work.lab_post_subject as
    select
        USUBJID,
        TRT01A,
        PARAMCD,
        PARAM,

        max(POST_STATUS = "LOW") as HAS_LOW,
        max(POST_STATUS = "NORMAL") as HAS_NORMAL,
        max(POST_STATUS = "HIGH") as HAS_HIGH

    from work.lab_postbaseline
    group by USUBJID, TRT01A, PARAMCD, PARAM;
quit;


/*--------------------------------------------------------------
  STEP 5: Derive post-baseline status category
--------------------------------------------------------------*/

data work.lab_post_subject;
    set work.lab_post_subject;

    length POST_WORST_STATUS $20;

    if HAS_LOW = 1 and HAS_HIGH = 1 then
        POST_WORST_STATUS = "BOTH LOW AND HIGH";
    else if HAS_HIGH = 1 then
        POST_WORST_STATUS = "HIGH";
    else if HAS_LOW = 1 then
        POST_WORST_STATUS = "LOW";
    else if HAS_NORMAL = 1 then
        POST_WORST_STATUS = "NORMAL";
    else
        POST_WORST_STATUS = "UNKNOWN";
run;


/*--------------------------------------------------------------
  STEP 6: Join baseline and post-baseline status
--------------------------------------------------------------*/

proc sql;
    create table work.lab_shift_subject as
    select
        a.USUBJID,
        a.TRT01A,
        a.PARAMCD,
        a.PARAM,
        coalesce(b.BASE_STATUS, "NO BASELINE") as BASE_STATUS length=20,
        a.POST_WORST_STATUS

    from work.lab_post_subject as a

    left join work.lab_baseline as b
        on a.USUBJID = b.USUBJID
        and a.PARAMCD = b.PARAMCD;
quit;


/*--------------------------------------------------------------
  STEP 7: Create baseline-to-post-baseline shift summary
--------------------------------------------------------------*/

proc sql;
    create table outtab.lab_shift as
    select
        TRT01A,
        PARAMCD,
        PARAM,
        BASE_STATUS,
        POST_WORST_STATUS,

        count(*) as N_SUBJECT_PARAMETERS

    from work.lab_shift_subject

    group by
        TRT01A,
        PARAMCD,
        PARAM,
        BASE_STATUS,
        POST_WORST_STATUS

    order by
        TRT01A,
        PARAMCD,
        BASE_STATUS,
        POST_WORST_STATUS;
quit;


/*--------------------------------------------------------------
  STEP 8: Check duplicate subject/parameter records
--------------------------------------------------------------*/

proc sql;
    create table work.lab_shift_subject_qc as
    select
        USUBJID,
        PARAMCD,
        count(*) as RECORD_COUNT
    from work.lab_shift_subject
    group by USUBJID, PARAMCD
    having calculated RECORD_COUNT > 1;
quit;


/*--------------------------------------------------------------
  STEP 9: Reconcile input and summarized subject/parameter counts
--------------------------------------------------------------*/

proc sql noprint;
    select count(*)
    into :input_subjparm trimmed
    from work.lab_post_subject;

    select sum(N_SUBJECT_PARAMETERS)
    into :sum_subjparm trimmed
    from outtab.lab_shift;
quit;

data outtab.lab_shift_recon;
    INPUT_SUBJPARM = &input_subjparm;
    SUM_SUBJPARM = &sum_subjparm;

    DIFFERENCE = INPUT_SUBJPARM - SUM_SUBJPARM;

    if DIFFERENCE = 0 then QC_PASS = 1;
    else QC_PASS = 0;
run;


/*--------------------------------------------------------------
  STEP 10: Create overall laboratory shift QC summary
--------------------------------------------------------------*/

proc sql noprint;
    select count(*)
    into :baseline_records trimmed
    from work.lab_baseline;

    select count(*)
    into :base_duplicates trimmed
    from work.lab_baseline_duplicates;

    select count(*)
    into :postbase_records trimmed
    from work.lab_postbaseline;

    select count(*)
    into :postbase_subjparm trimmed
    from work.lab_post_subject;

    select count(*)
    into :subjparm_duplicates trimmed
    from work.lab_shift_subject_qc;

    select count(*)
    into :subjparm_no_base trimmed
    from work.lab_shift_subject
    where BASE_STATUS = "NO BASELINE";
quit;


data outtab.lab_shift_qc;

    BASELINE_RECORDS = &baseline_records;
    BASE_DUPLICATES = &base_duplicates;
    POSTBASE_RECORDS = &postbase_records;
    POSTBASE_SUBJPARM = &postbase_subjparm;
    SUBJPARM_DUPLICATES = &subjparm_duplicates;
    SUBJPARM_NO_BASE = &subjparm_no_base;

    if BASE_DUPLICATES = 0
       and SUBJPARM_DUPLICATES = 0 then
        QC_PASS = 1;
    else
        QC_PASS = 0;

run;


/*--------------------------------------------------------------
  STEP 11: Display QC results
--------------------------------------------------------------*/

title "Laboratory Shift QC Summary";

proc print data=outtab.lab_shift_qc noobs;
run;


title "Laboratory Shift Reconciliation";

proc print data=outtab.lab_shift_recon noobs;
run;


title "Baseline Duplicate QC";

proc print data=work.lab_baseline_duplicates noobs;
run;


title "Subject/Parameter Duplicate QC";

proc print data=work.lab_shift_subject_qc noobs;
run;


/*--------------------------------------------------------------
  STEP 12: Display sample laboratory shift results
--------------------------------------------------------------*/

title "Baseline-to-Post-Baseline Laboratory Status Shifts";

proc print data=outtab.lab_shift(obs=30) noobs;
run;


/*--------------------------------------------------------------
  STEP 13: Output inventory
--------------------------------------------------------------*/

title "Laboratory Shift Output Dataset Inventory";

proc contents data=outtab.lab_shift;
run;

proc contents data=outtab.lab_shift_qc;
run;

proc contents data=outtab.lab_shift_recon;
run;

title;