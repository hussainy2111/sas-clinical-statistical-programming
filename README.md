# SAS Clinical Statistical Programming Portfolio

## Project Overview

An independent SAS clinical statistical programming portfolio project focused on clinical trial data processing, analysis dataset derivation, statistical summaries, and quality control.

The project demonstrates the application of SAS programming techniques to clinical trial source data, transforming subject-level and domain-specific records into analysis-ready datasets and producing treatment-group summaries.

The workflow emphasizes data integrity, reproducibility, validation, and traceability throughout the programming process.

## Project Objectives

- Import and process clinical trial source datasets.
- Derive analysis-ready datasets using SAS DATA step programming and PROC SQL.
- Perform demographic, safety, laboratory, vital signs, exposure, and concomitant medication analyses.
- Implement data validation, quality control, and reconciliation procedures.
- Generate permanent analysis outputs and an integrated project report.

## Dataset Development

Six ADaM-style analysis datasets were developed:

| Dataset | Description |
|---|---|
| ADSL | Subject-level analysis dataset |
| ADAE | Adverse event analysis dataset |
| ADLB | Laboratory analysis dataset |
| ADVS | Vital signs analysis dataset |
| ADEX | Exposure analysis dataset |
| ADCM | Concomitant medication analysis dataset |

The derived datasets incorporate treatment information, subject-level population flags, analysis dates, baseline values, and relevant analysis variables.

## Statistical Programming and Analysis

### Demographics
- Age summaries by treatment group.
- Sex, race, and ethnicity frequency distributions.
- Subject counts and percentages.

### Adverse Events
- Adverse event summaries by treatment group.
- Severity and seriousness summaries.
- System Organ Class (SOC) and Preferred Term (PT) summaries.
- Partial-date handling and provisional treatment-emergent event classification.

### Laboratory Data
- Descriptive statistics by treatment, parameter, and visit.
- Post-baseline laboratory abnormality summaries.
- Baseline-to-post-baseline laboratory status shift analysis.
- Change-from-baseline and percentage change calculations.

### Vital Signs
- Baseline and post-baseline analysis.
- Descriptive statistics by treatment, parameter, visit, and position.
- Change-from-baseline summaries.

### Exposure
- Treatment exposure duration summaries.
- Recorded dose summaries by treatment group.
- Missing-date and duration quality checks.

### Concomitant Medications
- Medication summaries by treatment group.
- Medication classification summaries.
- Partial-date processing and treatment-relative timing assessment.

## Quality Control and Validation

A project-level QC framework was implemented to assess the consistency and accuracy of derived datasets and analysis outputs.

Validation activities included:

- Source-to-derived record count reconciliation.
- Subject-level linkage checks.
- Duplicate record key detection.
- Baseline flag consistency checks.
- Change-from-baseline calculation validation.
- Summary-level reconciliation.
- Missing and failed QC result assessment.

### Final Integrated QC Results

| QC Metric | Result |
|---|---:|
| QC datasets | 11 |
| Individual QC check rows | 270 |
| Passed checks | 270 |
| Failed checks | 0 |
| Missing QC results | 0 |
| Overall project QC status | PASS |

All 270 integrated QC check rows passed.

## Technical Skills Demonstrated

- **SAS:** DATA step, PROC SQL, PROC MEANS, PROC FREQ, sorting, merging, macros, ODS reporting.
- **Clinical data programming:** SDTM-style source data processing, ADaM-style dataset derivation, treatment and population variables, baseline and change-from-baseline derivations.
- **Statistical programming:** Descriptive statistics, frequency distributions, treatment-group summaries, laboratory and safety analyses.
- **Data quality:** Validation, reconciliation, duplicate detection, subject linkage, derivation checks, and QC reporting.
- **Reproducible programming:** Structured SAS programs, permanent output datasets, documentation, and integrated reporting.

## Repository Structure

```text
sas-clinical-statistical-programming/
│
├── README.md
│
├── programs/
│   └── SAS programming scripts
│
├── outputs/
│   ├── tables/
│   └── report/
│
└── documentation/
    └── QC summary and project documentation
```

## Project Deliverables

- Six derived ADaM-style analysis datasets.
- Demographic and clinical domain analysis tables.
- Dataset-level QC outputs.
- Integrated project QC summary.
- Dataset inventory.
- Final PDF project report.
- Reproducible SAS programming scripts.

## Project Scope and Limitations

This is an independent portfolio project intended to demonstrate transferable SAS clinical statistical programming skills.

The analysis conventions are illustrative and are not represented as protocol- or Statistical Analysis Plan (SAP)-validated production analyses. The project does not claim complete CDISC conformance, regulatory submission readiness, direct EDC system integration, Medidata Rave experience, or production CTMS/PDI implementation.

## Author

Bioinformatician with experience in large-scale biomedical data analysis, statistical modeling, reproducible workflows, data quality control, and analysis-ready dataset development.

Technical interests include clinical statistical programming, clinical data integration, and scientific data engineering.
