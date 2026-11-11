
/***************************************************************
 PROGRAM: 16_FINAL_PROJECT_REPORT.sas
 PURPOSE: Generate final clinical programming portfolio report
 OUTPUT:
   OUTTAB.PROJECT_DATASET_INVENTORY
   OUTTAB.PROJECT_LIBRARY_INVENTORY
   outputs/tables/FINAL_CLINICAL_PROGRAMMING_REPORT.pdf
***************************************************************/

options nodate nonumber;
ods graphics off;

/*-------------------------------------------------------------*
 | 1. LIBRARY ASSIGNMENTS
 *-------------------------------------------------------------*/

libname SDTM "/home/u64646326/clinical_trial_project/data/source";
libname ADAM "/home/u64646326/clinical_trial_project/data/analysis";
libname OUTTAB "/home/u64646326/clinical_trial_project/outputs/tables";

/*-------------------------------------------------------------*
 | 2. CREATE PERMANENT DATASET INVENTORY
 *-------------------------------------------------------------*/

proc sql;
    create table OUTTAB.PROJECT_DATASET_INVENTORY as
    select
        libname as LIBRARY length=8,
        memname as DATASET_NAME length=32,
        nobs as OBSERVATIONS
    from dictionary.tables
    where libname in ("SDTM","ADAM","OUTTAB")
      and memtype = "DATA"
    order by libname, memname;
quit;

/*-------------------------------------------------------------*
 | 3. CREATE LIBRARY-LEVEL INVENTORY SUMMARY
 *-------------------------------------------------------------*/

proc sql;
    create table OUTTAB.PROJECT_LIBRARY_INVENTORY as
    select
        LIBRARY,
        count(*) as NUMBER_OF_DATASETS,
        sum(OBSERVATIONS) as TOTAL_OBSERVATIONS
    from OUTTAB.PROJECT_DATASET_INVENTORY
    group by LIBRARY
    order by LIBRARY;
quit;

/*-------------------------------------------------------------*
 | 4. OPEN FINAL PDF REPORT
 *-------------------------------------------------------------*/

ods pdf file=
"/home/u64646326/clinical_trial_project/outputs/tables/FINAL_CLINICAL_PROGRAMMING_REPORT.pdf"
style=journal
notoc;

/*-------------------------------------------------------------*
 | 5. PROJECT OVERVIEW
 *-------------------------------------------------------------*/

title1 "CLINICAL STATISTICAL PROGRAMMING PORTFOLIO";
title2 "Final Project Report";

ods text=" ";
ods text="Project overview";
ods text="This portfolio project demonstrates a reproducible SAS workflow using clinical trial data. Source datasets were used to derive analysis datasets, produce descriptive and safety summaries, and perform dataset-level and integrated quality control.";

ods text=" ";
ods text="Programming scope";
ods text="The project includes subject-level data, adverse events, laboratory results, vital signs, exposure, concomitant medications, demographic summaries, and derived analysis datasets.";

ods text=" ";
ods text="Population";
ods text="The safety population contains 254 subjects: 86 assigned to placebo, 72 to high-dose treatment, and 96 to low-dose treatment. The source subject-level dataset contains 306 subjects.";

ods text=" ";
ods text="Important interpretation";
ods text="Some analysis conventions, including treatment-emergent adverse event classification and certain laboratory summaries, are portfolio-level derivations. They should not be interpreted as protocol- or SAP-validated production analyses.";

/*-------------------------------------------------------------*
 | 6. FINAL INTEGRATED QC SUMMARY
 *-------------------------------------------------------------*/

title1 "FINAL INTEGRATED QUALITY CONTROL SUMMARY";

proc print data=OUTTAB.PROJECT_QC_SUMMARY noobs label;
run;

/*-------------------------------------------------------------*
 | 7. QC RESULTS BY DATASET
 *-------------------------------------------------------------*/

title1 "QUALITY CONTROL RESULTS BY DATASET";

proc print data=OUTTAB.PROJECT_QC_STATUS noobs label;
run;

/*-------------------------------------------------------------*
 | 8. LIBRARY INVENTORY
 *-------------------------------------------------------------*/

title1 "DATASET INVENTORY BY LIBRARY";

proc print data=OUTTAB.PROJECT_LIBRARY_INVENTORY noobs label;
run;

/*-------------------------------------------------------------*
 | 9. COMPLETE DATASET INVENTORY
 *-------------------------------------------------------------*/

title1 "COMPLETE PROJECT DATASET INVENTORY";

proc print data=OUTTAB.PROJECT_DATASET_INVENTORY noobs label;
run;

/*-------------------------------------------------------------*
 | 10. SELECTED ANALYSIS OUTPUTS
 *-------------------------------------------------------------*/

%macro print_if_exists(data=, description=, obs=20);

    %if %sysfunc(exist(&data)) %then %do;

        title1 "&description";

        proc print data=&data(obs=&obs) noobs;
        run;

    %end;
    %else %do;

        %put NOTE: &data was not found. This section was skipped.;

    %end;

%mend;

/* Demographics */

%print_if_exists(
    data=OUTTAB.DEMOG_AGE,
    description=DEMOGRAPHIC AGE SUMMARY,
    obs=20
);

%print_if_exists(
    data=OUTTAB.DEMOG_CATEGORICAL,
    description=DEMOGRAPHIC CATEGORICAL SUMMARY,
    obs=30
);

/* Adverse events */

%print_if_exists(
    data=OUTTAB.ADAE_QC,
    description=ADVERSE EVENT DERIVATION QUALITY CONTROL,
    obs=20
);

/* Laboratory analyses */

%print_if_exists(
    data=OUTTAB.ADLB_QC,
    description=LABORATORY ADAM DERIVATION QUALITY CONTROL,
    obs=20
);

%print_if_exists(
    data=OUTTAB.LAB_ABNORMALITY_RECON,
    description=LABORATORY ABNORMALITY RECONCILIATION,
    obs=20
);

%print_if_exists(
    data=OUTTAB.LAB_SHIFT_RECON,
    description=LABORATORY SHIFT RECONCILIATION,
    obs=20
);

/* Vital signs */

%print_if_exists(
    data=OUTTAB.VS_QC,
    description=VITAL SIGNS DERIVATION QUALITY CONTROL,
    obs=20
);

/* Exposure and concomitant medications */

%print_if_exists(
    data=OUTTAB.EXPOSURE_SUMMARY,
    description=EXPOSURE SUMMARY BY TREATMENT,
    obs=20
);

%print_if_exists(
    data=OUTTAB.CM_SUMMARY,
    description=CONCOMITANT MEDICATION SUMMARY,
    obs=20
);

/*-------------------------------------------------------------*
 | 11. REPORT CONCLUSION
 *-------------------------------------------------------------*/

title1 "PROJECT CONCLUSION";

ods text="The final integrated QC summary contains 11 QC datasets and 270 individual QC rows. All 270 rows passed, with zero failed checks and zero missing QC results.";

ods text="The project produced six ADaM datasets containing 98,536 observations. The analysis outputs include demographic summaries, adverse event analyses, laboratory descriptive and categorical assessments, vital signs summaries, exposure summaries, and concomitant medication summaries.";

ods text="This project demonstrates SAS data derivation, statistical programming, descriptive analysis, data reconciliation, quality control, and reproducible reporting using clinical trial data.";

ods text="End of report.";

/*-------------------------------------------------------------*
 | 12. CLOSE PDF
 *-------------------------------------------------------------*/

title;
footnote;

ods pdf close;

%put NOTE: FINAL CLINICAL PROGRAMMING REPORT GENERATED.;
%put NOTE: PDF location: /home/u64646326/clinical_trial_project/outputs/tables/FINAL_CLINICAL_PROGRAMMING_REPORT.pdf;
