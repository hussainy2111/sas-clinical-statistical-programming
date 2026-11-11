
/***************************************************************
 Program: 06_ae_tables.sas

 Purpose:
   Prepare the safety population and generate adverse event
   incidence summaries and SOC-level summary tables.

 Inputs:
   ADAM.ADSL
   ADAM.ADAE

 Outputs:
   WORK.SAFETY_ADSL
   WORK.AE_DENOMINATORS
   WORK.AE_SAFETY
   WORK.AE_OVERALL_SUMMARY
   WORK.AE_SOC_SUMMARY

 Project:
   Clinical Trial Statistical Programming Portfolio

 Population:
   Safety population (SAFFL = "Y")

 AE Scope:
   All recorded AE records, not TEAEs only.
***************************************************************/


/*-------------------------------------------------------------*
 | STEP 1: PROJECT PATHS AND LIBRARY ASSIGNMENTS
 *-------------------------------------------------------------*/

%let project = /home/u64646326/clinical_trial_project;

libname adam "&project./data/analysis";


/*-------------------------------------------------------------*
 | STEP 2: VERIFY INPUT DATASETS
 *-------------------------------------------------------------*/

%put NOTE: Checking ADSL and ADAE input datasets.;

%if not %sysfunc(exist(adam.adsl)) %then %do;
    %put ERROR: ADAM.ADSL does not exist.;
    %abort cancel;
%end;

%if not %sysfunc(exist(adam.adae)) %then %do;
    %put ERROR: ADAM.ADAE does not exist.;
    %abort cancel;
%end;

proc contents data=adam.adsl varnum;
    title "ADSL Dataset Structure";
run;

proc contents data=adam.adae varnum;
    title "ADAE Dataset Structure";
run;

title;


/*-------------------------------------------------------------*
 | STEP 3: CHECK ADSL SUBJECT UNIQUENESS
 *-------------------------------------------------------------*/

proc sql;
    create table work.adsl_duplicate_check as
    select
        USUBJID,
        count(*) as RECORD_COUNT
    from adam.adsl
    group by USUBJID
    having count(*) > 1;
quit;

title "ADSL Duplicate Subject Check";

proc print data=work.adsl_duplicate_check noobs;
run;

title;


/*-------------------------------------------------------------*
 | STEP 4: CHECK SAFETY POPULATION AND TREATMENT ASSIGNMENTS
 *-------------------------------------------------------------*/

proc freq data=adam.adsl;
    tables SAFFL*TRT01A / missing;
    title "Safety Population by Actual Treatment";
run;

proc freq data=adam.adsl;
    tables SAFFL / missing;
    title "Safety Population Flag Distribution";
run;

title;


/*-------------------------------------------------------------*
 | STEP 5: CREATE SAFETY POPULATION DATASET
 *-------------------------------------------------------------*/

data work.safety_adsl;
    set adam.adsl;

    where SAFFL = "Y";

    keep STUDYID
         USUBJID
         TRT01P
         TRT01A
         SAFFL;
run;


/*-------------------------------------------------------------*
 | STEP 6: CALCULATE SAFETY POPULATION DENOMINATORS
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_denominators as
    select
        TRT01A,
        count(distinct USUBJID) as SAFETY_N
    from work.safety_adsl
    group by TRT01A
    order by TRT01A;
quit;

title "Safety Population Denominators by Actual Treatment";

proc print data=work.ae_denominators noobs;
run;

title;


/*-------------------------------------------------------------*
 | STEP 7: PREPARE AE RECORDS FOR THE SAFETY POPULATION
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_safety as
    select
        a.*,
        b.SAFFL as ADSL_SAFFL
    from adam.adae as a
    inner join work.safety_adsl as b
        on a.USUBJID = b.USUBJID;
quit;


/*-------------------------------------------------------------*
 | STEP 8: BASIC AE POPULATION CHECKS
 *-------------------------------------------------------------*/

title "Safety Population AE Record Summary";

proc sql;
    select
        count(*) as TOTAL_AE_RECORDS,
        count(distinct USUBJID) as SUBJECTS_WITH_AE,
        count(distinct case
            when AESER = "Y" then USUBJID
        end) as SUBJECTS_WITH_SERIOUS_AE
    from work.ae_safety;

    title "AE Records by Actual Treatment";

    select
        TRT01A,
        count(*) as AE_RECORDS,
        count(distinct USUBJID) as SUBJECTS_WITH_AE
    from work.ae_safety
    group by TRT01A
    order by TRT01A;
quit;

title;


/*-------------------------------------------------------------*
 | STEP 9: CHECK AE RECORDS WITHOUT A SAFETY POPULATION MATCH
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_not_in_safety as
    select
        a.USUBJID,
        a.AESEQ,
        a.AETERM,
        a.SAFFL
    from adam.adae as a
    left join work.safety_adsl as b
        on a.USUBJID = b.USUBJID
    where missing(b.USUBJID);
quit;

title "AE Records Not Matched to Safety Population";

proc sql;
    select
        count(*) as UNMATCHED_AE_RECORDS,
        count(distinct USUBJID) as UNMATCHED_SUBJECTS
    from work.ae_not_in_safety;
quit;

title;


/***************************************************************
 STEP 10: OVERALL ADVERSE EVENT INCIDENCE SUMMARY

 Output:
   WORK.AE_OVERALL_SUMMARY

 Denominator:
   Safety population by actual treatment.

 Counts:
   Distinct subjects with at least one event in each category.
***************************************************************/


/*-------------------------------------------------------------*
 | 10.1 Create subject-level AE category flags
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_subject_summary as
    select
        USUBJID,
        TRT01A,

        max(1) as ANY_AE,

        max(case
            when AESER = "Y" then 1
            else 0
        end) as SERIOUS_AE,

        max(case
            when AESER = "N" then 1
            else 0
        end) as NONSERIOUS_AE,

        max(case
            when upcase(strip(AESEV)) = "MILD" then 1
            else 0
        end) as MILD_AE,

        max(case
            when upcase(strip(AESEV)) = "MODERATE" then 1
            else 0
        end) as MODERATE_AE,

        max(case
            when upcase(strip(AESEV)) = "SEVERE" then 1
            else 0
        end) as SEVERE_AE

    from work.ae_safety
    group by USUBJID, TRT01A;
quit;


/*-------------------------------------------------------------*
 | 10.2 Summarize subject counts by treatment
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_subject_counts as
    select
        TRT01A,
        count(*) as ANY_AE,
        sum(SERIOUS_AE) as SERIOUS_AE,
        sum(NONSERIOUS_AE) as NONSERIOUS_AE,
        sum(MILD_AE) as MILD_AE,
        sum(MODERATE_AE) as MODERATE_AE,
        sum(SEVERE_AE) as SEVERE_AE
    from work.ae_subject_summary
    group by TRT01A;
quit;


/*-------------------------------------------------------------*
 | 10.3 Combine counts with safety population denominators
 *-------------------------------------------------------------*/

proc sort data=work.ae_denominators;
    by TRT01A;
run;

proc sort data=work.ae_subject_counts;
    by TRT01A;
run;

data work.ae_overall_summary;
    merge work.ae_denominators(in=in_denominator)
          work.ae_subject_counts;
    by TRT01A;

    if in_denominator;

    PCT_ANY_AE =
        (ANY_AE / SAFETY_N) * 100;

    PCT_SERIOUS_AE =
        (SERIOUS_AE / SAFETY_N) * 100;

    PCT_NONSERIOUS_AE =
        (NONSERIOUS_AE / SAFETY_N) * 100;

    PCT_MILD_AE =
        (MILD_AE / SAFETY_N) * 100;

    PCT_MODERATE_AE =
        (MODERATE_AE / SAFETY_N) * 100;

    PCT_SEVERE_AE =
        (SEVERE_AE / SAFETY_N) * 100;

    format PCT_: 6.1;
run;


/*-------------------------------------------------------------*
 | 10.4 Display overall AE incidence summary
 *-------------------------------------------------------------*/

title "Overall Adverse Event Incidence - Safety Population";

proc print data=work.ae_overall_summary noobs label;
    var TRT01A
        SAFETY_N
        ANY_AE PCT_ANY_AE
        SERIOUS_AE PCT_SERIOUS_AE
        NONSERIOUS_AE PCT_NONSERIOUS_AE
        MILD_AE PCT_MILD_AE
        MODERATE_AE PCT_MODERATE_AE
        SEVERE_AE PCT_SEVERE_AE;

    label
        TRT01A = "Actual Treatment"
        SAFETY_N = "Safety Population N"
        ANY_AE = "Subjects with Any AE"
        PCT_ANY_AE = "Any AE (%)"
        SERIOUS_AE = "Subjects with Serious AE"
        PCT_SERIOUS_AE = "Serious AE (%)"
        NONSERIOUS_AE = "Subjects with Non-serious AE"
        PCT_NONSERIOUS_AE = "Non-serious AE (%)"
        MILD_AE = "Subjects with Mild AE"
        PCT_MILD_AE = "Mild AE (%)"
        MODERATE_AE = "Subjects with Moderate AE"
        PCT_MODERATE_AE = "Moderate AE (%)"
        SEVERE_AE = "Subjects with Severe AE"
        PCT_SEVERE_AE = "Severe AE (%)";

    title2 "Number and Percentage of Subjects";
run;

title;


/*-------------------------------------------------------------*
 | 10.5 QC: Verify subject counts do not exceed denominators
 *-------------------------------------------------------------*/

data work.ae_overall_qc;
    set work.ae_overall_summary;

    QC_ANY_AE =
        (ANY_AE <= SAFETY_N);

    QC_SERIOUS_AE =
        (SERIOUS_AE <= SAFETY_N);

    QC_NONSERIOUS_AE =
        (NONSERIOUS_AE <= SAFETY_N);

    QC_SEVERITY =
        (MILD_AE <= SAFETY_N and
         MODERATE_AE <= SAFETY_N and
         SEVERE_AE <= SAFETY_N);
run;

title "Overall AE Summary QC";

proc print data=work.ae_overall_qc noobs;
    var TRT01A
        SAFETY_N
        QC_ANY_AE
        QC_SERIOUS_AE
        QC_NONSERIOUS_AE
        QC_SEVERITY;
run;

title;


/***************************************************************
 STEP 11: ADVERSE EVENT SUMMARY BY SYSTEM ORGAN CLASS (SOC)

 Output:
   WORK.AE_SOC_SUMMARY

 Measures:
   - Number of AE records
   - Number of distinct subjects with an AE
   - Percentage of safety population with an AE
***************************************************************/


/*-------------------------------------------------------------*
 | 11.1 Prepare SOC-level AE records
 *-------------------------------------------------------------*/

data work.ae_soc_records;
    set work.ae_safety;

    length SOC_ANALYSIS $100;

    if missing(AESOC_ANALYSIS) then
        SOC_ANALYSIS = "Uncoded/Not Reported";
    else
        SOC_ANALYSIS = strip(AESOC_ANALYSIS);
run;


/*-------------------------------------------------------------*
 | 11.2 Count AE records and distinct subjects by SOC
 *-------------------------------------------------------------*/

proc sql;
    create table work.ae_soc_counts as
    select
        TRT01A,
        SOC_ANALYSIS,
        count(*) as AE_RECORDS,
        count(distinct USUBJID) as SUBJECTS_WITH_AE
    from work.ae_soc_records
    group by TRT01A, SOC_ANALYSIS;
quit;


/*-------------------------------------------------------------*
 | 11.3 Add safety population denominators
 *-------------------------------------------------------------*/

proc sort data=work.ae_soc_counts;
    by TRT01A;
run;

proc sort data=work.ae_denominators;
    by TRT01A;
run;

data work.ae_soc_summary;
    merge work.ae_soc_counts(in=in_ae)
          work.ae_denominators(in=in_denominator);
    by TRT01A;

    if in_ae and in_denominator;

    PCT_SUBJECTS_WITH_AE =
        (SUBJECTS_WITH_AE / SAFETY_N) * 100;

    format PCT_SUBJECTS_WITH_AE 6.1;
run;


/*-------------------------------------------------------------*
 | 11.4 Sort SOC results by subject frequency
 *-------------------------------------------------------------*/

proc sort data=work.ae_soc_summary;
    by TRT01A
       descending SUBJECTS_WITH_AE
       descending AE_RECORDS
       SOC_ANALYSIS;
run;


/*-------------------------------------------------------------*
 | 11.5 Display SOC summary
 *-------------------------------------------------------------*/

title "Adverse Events by System Organ Class";
title2 "Safety Population - All Recorded AE Records";

proc print data=work.ae_soc_summary noobs label;
    var TRT01A
        SOC_ANALYSIS
        SAFETY_N
        AE_RECORDS
        SUBJECTS_WITH_AE
        PCT_SUBJECTS_WITH_AE;

    label
        TRT01A = "Actual Treatment"
        SOC_ANALYSIS = "System Organ Class"
        SAFETY_N = "Safety Population N"
        AE_RECORDS = "Number of AE Records"
        SUBJECTS_WITH_AE = "Subjects with AE"
        PCT_SUBJECTS_WITH_AE = "Subjects with AE (%)";
run;

title;


/*-------------------------------------------------------------*
 | 11.6 QC: SOC subject counts and percentages
 *-------------------------------------------------------------*/

data work.ae_soc_qc;
    set work.ae_soc_summary;

    QC_SUBJECT_COUNT =
        (SUBJECTS_WITH_AE <= SAFETY_N);

    QC_PERCENTAGE =
        (PCT_SUBJECTS_WITH_AE >= 0 and
         PCT_SUBJECTS_WITH_AE <= 100);

    QC_DENOMINATOR =
        (SAFETY_N > 0);
run;

title "QC: Adverse Events by System Organ Class";

proc print data=work.ae_soc_qc noobs;
    var TRT01A
        SOC_ANALYSIS
        SAFETY_N
        SUBJECTS_WITH_AE
        PCT_SUBJECTS_WITH_AE
        QC_SUBJECT_COUNT
        QC_PERCENTAGE
        QC_DENOMINATOR;
run;

title;


/*-------------------------------------------------------------*
 | 11.7 Reconcile SOC event counts against total AE records
 *-------------------------------------------------------------*/

/* Obtain total AE record count */

proc sql noprint;
    select count(*)
    into :TOTAL_AE trimmed
    from work.ae_safety;
quit;


/* Obtain total SOC event record count */

proc sql noprint;
    select sum(AE_RECORDS)
    into :SOC_AE trimmed
    from work.ae_soc_summary;
quit;


/* Calculate reconciliation difference */

data work.ae_soc_reconciliation;

    TOTAL_AE_RECORDS = &TOTAL_AE;
    SOC_AE_RECORDS = &SOC_AE;

    DIFFERENCE =
        SOC_AE_RECORDS - TOTAL_AE_RECORDS;

run;


/* Display reconciliation */

title "QC: SOC Event Record Reconciliation";

proc print data=work.ae_soc_reconciliation noobs;
run;

title;


/***************************************************************
 END OF PROGRAM
***************************************************************/

%put NOTE: 06_ae_tables.sas completed.;

