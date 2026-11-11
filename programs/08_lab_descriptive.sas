
/*==============================================================*
 | 08_LAB_DESCRIPTIVE.SAS
 | Purpose: Descriptive summaries of numeric laboratory results
 | Source:  ADAM.ADLB
 | Output:  LAB_DESCRIPTIVE and QC datasets
 *==============================================================*/

%let project=/home/u64646326/clinical_trial_project;

libname adam "&project./data/analysis";

options dlcreatedir;
libname outtab "&project./outputs/tables";
options nodlcreatedir;


/* STEP 1: Clear previous WORK datasets */

proc datasets library=work nolist;
    delete lab_numeric
           lab_descriptive
           lab_summary_qc
           lab_missing_qc
           lab_parameter_counts
           lab_summary_reconciliation;
quit;


/* STEP 2: Select numeric laboratory results */

data work.lab_numeric;
    set adam.adlb;

    where not missing(AVAL);

    keep STUDYID USUBJID TRT01A PARAMCD PARAM
         VISITNUM VISIT ADT AVAL BASE CHG PCHG
         ABLFL ANRIND ANRLO ANRHI DTYPE;
run;


/* STEP 3: Numeric records by parameter */

proc sql;
    create table work.lab_parameter_counts as
    select PARAMCD,
           PARAM,
           count(*) as NUMERIC_RECORDS,
           count(distinct USUBJID) as SUBJECTS
    from work.lab_numeric
    group by PARAMCD, PARAM
    order by PARAMCD;
quit;

title "Numeric Laboratory Records by Parameter";

proc print data=work.lab_parameter_counts noobs;
run;


/* STEP 4: Descriptive statistics */

proc sort data=work.lab_numeric;
    by TRT01A PARAMCD PARAM VISITNUM VISIT;
run;

proc means data=work.lab_numeric noprint;
    by TRT01A PARAMCD PARAM VISITNUM VISIT;
    var AVAL;

    output out=work.lab_descriptive
        (drop=_TYPE_ _FREQ_)
        n=N
        mean=MEAN
        std=SD
        median=MEDIAN
        min=MIN
        max=MAX;
run;


/* STEP 5: Labels and formats */

data work.lab_descriptive;
    set work.lab_descriptive;

    label TRT01A="Actual Treatment"
          PARAMCD="Laboratory Parameter Code"
          PARAM="Laboratory Parameter"
          VISITNUM="Visit Number"
          VISIT="Visit Name"
          N="Number of Numeric Results"
          MEAN="Mean"
          SD="Standard Deviation"
          MEDIAN="Median"
          MIN="Minimum"
          MAX="Maximum";

    format MEAN SD MEDIAN MIN MAX 12.3;
run;


/* STEP 6: Display descriptive summary */

title "Descriptive Laboratory Summary by Treatment and Visit";

proc print data=work.lab_descriptive noobs label;
    var TRT01A PARAMCD PARAM VISITNUM VISIT
        N MEAN SD MEDIAN MIN MAX;
run;


/* STEP 7: Check duplicate summary groups */

proc sql;
    create table work.lab_summary_qc as
    select TRT01A,
           PARAMCD,
           VISITNUM,
           VISIT,
           count(*) as SUMMARY_ROWS
    from work.lab_descriptive
    group by TRT01A, PARAMCD, VISITNUM, VISIT
    having count(*) ne 1;
quit;

title "QC: Duplicate Laboratory Summary Groups";

proc sql;
    select count(*) as DUPLICATE_SUMMARY_GROUPS
    from work.lab_summary_qc;
quit;


/* STEP 8: Reconcile input and summarized records */

proc sql noprint;
    select count(*)
    into :input_records trimmed
    from work.lab_numeric;

    select sum(N)
    into :summarized_records trimmed
    from work.lab_descriptive;
quit;

data work.lab_summary_reconciliation;
    INPUT_NUMERIC_RECORDS=&input_records;
    SUMMARIZED_NUMERIC_RECORDS=&summarized_records;

    DIFFERENCE=INPUT_NUMERIC_RECORDS-
               SUMMARIZED_NUMERIC_RECORDS;

    if DIFFERENCE=0 then QC_PASS=1;
    else QC_PASS=0;

    label INPUT_NUMERIC_RECORDS="Input Numeric Records"
          SUMMARIZED_NUMERIC_RECORDS="Summarized Numeric Records"
          DIFFERENCE="Reconciliation Difference"
          QC_PASS="Reconciliation QC Pass";
run;

title "QC: Numeric Laboratory Record Reconciliation";

proc print data=work.lab_summary_reconciliation noobs;
run;


/* STEP 9: Missing numeric results by parameter */

proc sql;
    create table work.lab_missing_qc as
    select PARAMCD,
           PARAM,
           count(*) as TOTAL_RECORDS,

           sum(case
               when missing(AVAL) then 1
               else 0
           end) as MISSING_NUMERIC_RESULTS,

           sum(case
               when not missing(AVAL) then 1
               else 0
           end) as AVAILABLE_NUMERIC_RESULTS

    from adam.adlb
    group by PARAMCD, PARAM
    order by PARAMCD;
quit;

title "QC: Numeric Result Availability by Parameter";

proc print data=work.lab_missing_qc noobs;
run;


/* STEP 10: Save permanent outputs */

data outtab.LAB_DESCRIPTIVE;
    set work.lab_descriptive;
run;

data outtab.LAB_PARAMETER_COUNTS;
    set work.lab_parameter_counts;
run;

data outtab.LAB_MISSING_QC;
    set work.lab_missing_qc;
run;

data outtab.LAB_SUMMARY_RECON;
    set work.lab_summary_reconciliation;
run;


/* STEP 11: Final output counts */

title "Final Laboratory Summary Output Counts";

proc sql;
    select "Laboratory Descriptive Summary" as DATASET length=40,
           count(*) as RECORDS
    from outtab.LAB_DESCRIPTIVE

    union all

    select "Laboratory Parameter Counts",
           count(*)
    from outtab.LAB_PARAMETER_COUNTS

    union all

    select "Laboratory Missing QC",
           count(*)
    from outtab.LAB_MISSING_QC

    union all

    select "Laboratory Reconciliation",
           count(*)
    from outtab.LAB_SUMMARY_RECON;
quit;


/* STEP 12: Completion */

%put NOTE: Laboratory descriptive summary completed.;
%put NOTE: Review all QC results and permanent outputs.;

title;
