
/***********************************************************************
 PROGRAM: 15_FINAL_INTEGRATED_QC.sas
 PURPOSE: Final integrated QC across all permanent project QC datasets.

 OUTPUT:
   OUTTAB.PROJECT_QC_STATUS
   OUTTAB.PROJECT_QC_SUMMARY
***********************************************************************/

options nonotes nostimer nosource nosyntaxcheck;

libname SDTM "/home/u64646326/clinical_trial_project/data/source";
libname ADAM "/home/u64646326/clinical_trial_project/data/analysis";
libname OUTTAB "/home/u64646326/clinical_trial_project/outputs/tables";


/*---------------------------------------------------------------*
 | 1. DISCOVER ALL QC DATASETS
 *---------------------------------------------------------------*/

proc sql noprint;

    select distinct memname
    into :QCLIST separated by " "
    from dictionary.columns
    where libname = "OUTTAB"
      and upcase(name) = "QC_PASS"
    order by memname;

quit;


/*---------------------------------------------------------------*
 | 2. INITIALIZE CONSOLIDATED QC TABLE
 *---------------------------------------------------------------*/

data work.project_qc_status;
    length QC_DATASET $32;
    length QC_ROWS QC_PASS_ROWS QC_FAIL_ROWS MISSING_QC_ROWS 8;
    stop;
run;


/*---------------------------------------------------------------*
 | 3. COLLECT QC RESULTS
 *---------------------------------------------------------------*/

%macro collect_qc;

    %let NQC = %sysfunc(countw(&QCLIST));

    %do I = 1 %to &NQC;

        %let DS = %scan(&QCLIST, &I);

        proc sql;

            create table work.qc_one as
            select
                "&DS" as QC_DATASET length=32,

                count(*) as QC_ROWS,

                sum(case
                    when QC_PASS = 1 then 1
                    else 0
                end) as QC_PASS_ROWS,

                sum(case
                    when QC_PASS ne 1 and not missing(QC_PASS)
                    then 1
                    else 0
                end) as QC_FAIL_ROWS,

                sum(case
                    when missing(QC_PASS) then 1
                    else 0
                end) as MISSING_QC_ROWS

            from OUTTAB.&DS;

        quit;

        proc append
            base=work.project_qc_status
            data=work.qc_one
            force;
        run;

    %end;

%mend collect_qc;

%collect_qc;


/*---------------------------------------------------------------*
 | 4. SAVE PER-DATASET QC RESULTS
 *---------------------------------------------------------------*/

proc sort data=work.project_qc_status;
    by QC_DATASET;
run;

data OUTTAB.PROJECT_QC_STATUS;
    set work.project_qc_status;
run;


/*---------------------------------------------------------------*
 | 5. CALCULATE OVERALL PROJECT QC STATUS
 *---------------------------------------------------------------*/

proc sql;

    create table OUTTAB.PROJECT_QC_SUMMARY as

    select
        count(*) as QC_DATASETS,
        sum(QC_ROWS) as TOTAL_QC_CHECK_ROWS,
        sum(QC_PASS_ROWS) as TOTAL_PASSED_ROWS,
        sum(QC_FAIL_ROWS) as TOTAL_FAILED_ROWS,
        sum(MISSING_QC_ROWS) as TOTAL_MISSING_QC_ROWS,

        case
            when sum(QC_FAIL_ROWS) = 0
             and sum(MISSING_QC_ROWS) = 0
             and sum(QC_ROWS) > 0
            then "PASS"
            else "REVIEW"
        end as PROJECT_QC_STATUS length=10

    from OUTTAB.PROJECT_QC_STATUS;

quit;


/*---------------------------------------------------------------*
 | 6. DISPLAY INDIVIDUAL QC RESULTS
 *---------------------------------------------------------------*/

title "Final Integrated QC by Dataset";

proc print data=OUTTAB.PROJECT_QC_STATUS noobs;
run;


/*---------------------------------------------------------------*
 | 7. DISPLAY OVERALL QC
 *---------------------------------------------------------------*/

title "Final Clinical Programming Project QC Summary";

proc print data=OUTTAB.PROJECT_QC_SUMMARY noobs;
run;


/*---------------------------------------------------------------*
 | 8. COUNT DERIVED ADAM DATASETS
 *---------------------------------------------------------------*/

title "Final ADaM Dataset Inventory";

proc sql;

    select
        count(*) as NUMBER_OF_ADAM_DATASETS,
        sum(nobs) as TOTAL_ADAM_OBSERVATIONS

    from dictionary.tables

    where libname = "ADAM"
      and memtype = "DATA";

quit;

title;
