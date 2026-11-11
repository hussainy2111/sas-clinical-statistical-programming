OPTIONS NONOTES NOSTIMER NOSOURCE NOSYNTAXCHECK;

/***************************************************************
  PROGRAM: 11_EXPOSURE_ANALYSIS.sas

  PURPOSE:
    Create subject-level exposure analysis dataset and
    treatment exposure summaries.

  INPUT:
    SDTM.EX
    ADAM.ADSL

  OUTPUT:
    ADAM.ADEX
    OUTTAB.EXPOSURE_SUMMARY
    OUTTAB.EXPOSURE_QC
****************************************************************/


/*--------------------------------------------------------------
  STEP 1: Convert exposure dates and derive record-level duration
--------------------------------------------------------------*/

data work.ex_records;
    set sdtm.ex;

    length EXTRT_ANALYSIS $40;

    EXTRT_ANALYSIS = strip(EXTRT);

    EXSTDT = input(EXSTDTC, yymmdd10.);
    EXENDT = input(EXENDTC, yymmdd10.);

    format EXSTDT EXENDT date9.;

    if not missing(EXSTDT) and not missing(EXENDT) then
        EXDUR = EXENDT - EXSTDT + 1;
    else
        EXDUR = .;

    label
        EXSTDT = "Exposure Start Date"
        EXENDT = "Exposure End Date"
        EXDUR = "Exposure Duration in Days"
        EXTRT_ANALYSIS = "Exposure Treatment";
run;


/*--------------------------------------------------------------
  STEP 2: Summarize exposure by subject
--------------------------------------------------------------*/

proc sql;
    create table work.ex_subject as
    select
        USUBJID,

        min(EXSTDT) as EXSTDT format=date9.,
        max(EXENDT) as EXENDT format=date9.,

        sum(EXDUR) as TOTAL_EXDUR,

        mean(EXDOSE) as MEAN_DOSE,
        min(EXDOSE) as MIN_DOSE,
        max(EXDOSE) as MAX_DOSE,

        count(*) as EX_RECORDS,

        count(distinct EXTRT) as N_EXPOSURE_TRT,

        max(EXDOSE) as MAX_EXDOSE

    from work.ex_records

    group by USUBJID;
quit;


/*--------------------------------------------------------------
  STEP 3: Derive treatment-level exposure information
--------------------------------------------------------------*/

proc sql;
    create table work.ex_treatment as
    select
        USUBJID,
        EXTRT_ANALYSIS,

        min(EXSTDT) as TRT_EXSTDT format=date9.,
        max(EXENDT) as TRT_EXENDT format=date9.,

        sum(EXDUR) as TRT_EXDUR,

        mean(EXDOSE) as TRT_MEAN_DOSE,
        min(EXDOSE) as TRT_MIN_DOSE,
        max(EXDOSE) as TRT_MAX_DOSE

    from work.ex_records

    group by USUBJID, EXTRT_ANALYSIS;
quit;


/*--------------------------------------------------------------
  STEP 4: Merge subject-level exposure with ADSL
--------------------------------------------------------------*/

proc sort data=adam.adsl out=work.adsl_sorted;
    by USUBJID;
run;

proc sort data=work.ex_subject;
    by USUBJID;
run;

data adam.adex;
    merge work.adsl_sorted(in=A)
          work.ex_subject(in=B);

    by USUBJID;

    if A;

    length EXPOFL $1;

    if B then EXPOFL = "Y";
    else EXPOFL = "N";

    label
        TOTAL_EXDUR = "Total Exposure Duration in Days"
        MEAN_DOSE = "Mean Recorded Dose"
        MIN_DOSE = "Minimum Recorded Dose"
        MAX_DOSE = "Maximum Recorded Dose"
        EX_RECORDS = "Number of Exposure Records"
        N_EXPOSURE_TRT = "Number of Exposure Treatments"
        EXPOFL = "Exposure Record Flag";
run;


/*--------------------------------------------------------------
  STEP 5: Create treatment-level exposure summary
--------------------------------------------------------------*/

proc sql;
    create table outtab.exposure_summary as
    select
        a.TRT01A,

        count(distinct a.USUBJID) as N_SUBJECTS,

        mean(b.TOTAL_EXDUR) as MEAN_EXPOSURE_DAYS,
        std(b.TOTAL_EXDUR) as SD_EXPOSURE_DAYS,
        median(b.TOTAL_EXDUR) as MEDIAN_EXPOSURE_DAYS,
        min(b.TOTAL_EXDUR) as MIN_EXPOSURE_DAYS,
        max(b.TOTAL_EXDUR) as MAX_EXPOSURE_DAYS,

        mean(b.MEAN_DOSE) as MEAN_RECORDED_DOSE,
        min(b.MIN_DOSE) as MIN_RECORDED_DOSE,
        max(b.MAX_DOSE) as MAX_RECORDED_DOSE

    from adam.adex as a

    left join work.ex_subject as b
        on a.USUBJID = b.USUBJID

    where a.SAFFL = "Y"

    group by a.TRT01A

    order by a.TRT01A;
quit;


/*--------------------------------------------------------------
  STEP 6: Exposure QC
--------------------------------------------------------------*/

proc sql noprint;

    select count(*)
    into :source_ex_records trimmed
    from sdtm.ex;

    select count(*)
    into :derived_ex_records trimmed
    from work.ex_records;

    select count(*)
    into :adsl_subjects trimmed
    from adam.adsl;

    select count(*)
    into :adex_subjects trimmed
    from adam.adex;

    select count(*)
    into :missing_ex_dates trimmed
    from work.ex_records
    where missing(EXSTDT) or missing(EXENDT);

    select count(*)
    into :invalid_ex_duration trimmed
    from work.ex_records
    where EXDUR < 0;

    select count(*)
    into :duplicate_ex_keys trimmed
    from (
        select USUBJID, EXSEQ
        from sdtm.ex
        group by USUBJID, EXSEQ
        having count(*) > 1
    );
quit;


data outtab.exposure_qc;

    SOURCE_EX_RECORDS = &source_ex_records;
    DERIVED_EX_RECORDS = &derived_ex_records;
    ADSL_SUBJECTS = &adsl_subjects;
    ADEX_SUBJECTS = &adex_subjects;
    MISSING_EX_DATES = &missing_ex_dates;
    INVALID_EX_DURATION = &invalid_ex_duration;
    DUPLICATE_EX_KEYS = &duplicate_ex_keys;

    if SOURCE_EX_RECORDS = DERIVED_EX_RECORDS
       and ADSL_SUBJECTS = ADEX_SUBJECTS
       and INVALID_EX_DURATION = 0
       and DUPLICATE_EX_KEYS = 0 then
        QC_PASS = 1;
    else
        QC_PASS = 0;

run;


/*--------------------------------------------------------------
  STEP 7: Display exposure summary
--------------------------------------------------------------*/

title "Subject-Level Exposure Dataset";

proc print data=adam.adex(obs=20) noobs;
run;


title "Exposure Summary by Treatment";

proc print data=outtab.exposure_summary noobs;
run;


title "Exposure QC Summary";

proc print data=outtab.exposure_qc noobs;
run;


/*--------------------------------------------------------------
  STEP 8: Output dataset inventory
--------------------------------------------------------------*/

title "ADEX Dataset Structure";

proc contents data=adam.adex varnum;
run;


title "Exposure Summary Dataset Structure";

proc contents data=outtab.exposure_summary varnum;
run;


title "Exposure QC Dataset Structure";

proc contents data=outtab.exposure_qc varnum;
run;

title;