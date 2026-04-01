# EHIAS — Electronic Hospital Information & Appointment System

> A relational MySQL database designed to manage end-to-end hospital operations: patient records, doctor scheduling, prescriptions, billing, and diagnostic lab reports — secured with role-based access control.

---

## Table of Contents

- [Overview](#overview)
- [Database Architecture](#database-architecture)
- [Schema — Table Definitions](#schema--table-definitions)
- [Entity Relationship Summary](#entity-relationship-summary)
- [Triggers](#triggers)
- [Stored Procedures](#stored-procedures)
- [Views](#views)
- [Analytical Queries](#analytical-queries)
- [Role-Based Access Control](#role-based-access-control)
- [Data Snapshot](#data-snapshot)
- [Business Problems Solved](#business-problems-solved)
- [Setup & Usage](#setup--usage)

---

## Overview

**EHIAS** (Electronic Hospital Information & Appointment System) is a normalized MySQL relational database that models the operational core of a mid-to-large hospital system. It manages entities across departments, medical professionals, patient care pathways, revenue cycles, and diagnostic workflows.

The system was populated from a denormalized flat-file export (`hospital_data_10000_rows.csv`) containing 10,000 rows of synthetic patient and operational records, and authenticated via a separate `doctor_credentials.csv` file listing 200 doctor login accounts.

**At a glance:**

| Component | Count |
|---|---|
| Tables | 7 |
| Triggers | 6 |
| Stored Procedures | 9 |
| Views | 5 |
| Analytical Queries | 11 |

---

## Database Architecture

```
ehias (Database)
│
├── departments          ← Master list of hospital departments
├── doctors              ← Medical staff, linked to departments
│
├── patients             ← Patient demographic records
│
├── appointments         ← Core transactional table; links patients ↔ doctors
│
├── prescriptions        ← Medications issued per appointment
├── labreports           ← Diagnostic test results per appointment (JSON)
├── bills                ← Financial records per appointment
│
└── doctor_credentials   ← Authentication table (external CSV source)
```

### Design Principles

- **3NF Normalization**: The flat CSV source was decomposed into 7 normalized tables eliminating all repeating groups and transitive dependencies.
- **Referential Integrity**: All inter-table relationships are enforced via `FOREIGN KEY` constraints.
- **Appointment as Central Hub**: The `appointments` table acts as the system's pivot — every clinical and financial event traces back to a single appointment record.
- **Audit Trails**: `bills.billdate` and `labreports.createdate` carry timestamps with `DEFAULT CURRENT_TIMESTAMP` for automatic logging.

---

## Schema — Table Definitions

### `departments`
Stores the 10 clinical departments of the hospital.

| Column | Type | Constraints |
|---|---|---|
| `departmentid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `name` | VARCHAR(50) | NOT NULL |

---

### `doctors`
Stores the 200 medical staff members, their specialization, role level, and department.

| Column | Type | Constraints |
|---|---|---|
| `doctorid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `name` | VARCHAR(50) | — |
| `specialization` | VARCHAR(100) | — |
| `role` | VARCHAR(50) | — |
| `departmentid` | INT | FK → `departments.departmentid` |

**Roles**: Senior, Consultant, Resident, Junior

**Specializations**: Cardiology, Neurology, Oncology, Orthopedics, Pediatrics, Psychiatry, Radiology, Dermatology, ENT, General

---

### `patients`
Stores the 2,000 patient demographic records.

| Column | Type | Constraints |
|---|---|---|
| `patientid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `name` | VARCHAR(50) | — |
| `dateofbirth` | DATE | — |
| `gender` | VARCHAR(2) | CHECK (`m`, `f`, `o`) |
| `phone` | VARCHAR(10) | — |

---

### `appointments`
The core transactional table linking patients to doctors at a scheduled time.

| Column | Type | Constraints |
|---|---|---|
| `appointmentid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `patientid` | INT | FK → `patients.patientid` |
| `doctorid` | INT | FK → `doctors.doctorid` |
| `appointmenttime` | DATETIME | — |
| `status` | VARCHAR(50) | CHECK (`Scheduled`, `Completed`, `Cancelled`) |

---

### `prescriptions`
Medication records linked to appointments.

| Column | Type | Constraints |
|---|---|---|
| `prescriptionid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `appointmentid` | INT | FK → `appointments.appointmentid` |
| `medication` | VARCHAR(50) | — |
| `dosage` | VARCHAR(50) | — |

**Top medications**: Painkiller, Cough Syrup, Insulin, Ibuprofen, Antibiotics, Vitamin D, Amoxicillin, Paracetamol

---

### `bills`
Financial records per appointment, tracking amounts and payment status.

| Column | Type | Constraints |
|---|---|---|
| `billid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `appointmentid` | INT | FK → `appointments.appointmentid` |
| `amount` | DECIMAL(10,2) | — |
| `paid` | TINYINT(1) | 0 = unpaid, 1 = paid |
| `billdate` | DATETIME | DEFAULT CURRENT_TIMESTAMP |

---

### `labreports`
Diagnostic test results stored as JSON text, linked per appointment.

| Column | Type | Constraints |
|---|---|---|
| `reportid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `appointmentid` | INT | FK → `appointments.appointmentid` |
| `amount` | DECIMAL(10,2) | — |
| `reportdata` | TEXT | JSON: WBC, RBC, Hemoglobin |
| `createdate` | DATETIME | DEFAULT CURRENT_TIMESTAMP |

---

## Entity Relationship Summary

```
departments ──< doctors >──< appointments >──< patients
                                │
                    ┌───────────┼──────────────┐
                    ▼           ▼              ▼
             prescriptions    bills       labreports
```

- One department has many doctors (`1:N`)
- One doctor can have many appointments (`1:N`)
- One patient can have many appointments (`1:N`)
- Each appointment may have one bill, one prescription, and one lab report (`1:0..1` each)

---

## Triggers

### `check_new_appointment` — BEFORE INSERT on `appointments`
Validates every new appointment against two rules: rejects if the time is in the past, and blocks the insert if the same doctor already has a Scheduled appointment at that exact time. Prevents backdated bookings and double-booking.

### `check_appointment_update` — BEFORE UPDATE on `appointments`
Same validation as the insert trigger but fires on updates. Prevents rescheduling to a past time and catches double-booking when a doctor or time is changed on an existing appointment.

### `prevent_doctor_delete` — BEFORE DELETE on `doctors`
Blocks deletion of any doctor who has upcoming Scheduled appointments. Protects data integrity beyond what foreign key constraints alone can enforce.

### `validate_patient_phone_insert` — BEFORE INSERT on `patients`
Validates that the phone number is exactly 10 numeric digits. Uses REGEXP to reject entries with non-digit characters or incorrect length.

### `validate_patient_phone_update` — BEFORE UPDATE on `patients`
Same phone validation as the insert trigger, applied on updates. Ensures phone data quality is maintained even when editing existing records.

### `auto_bill_on_completion` — AFTER UPDATE on `appointments`
When an appointment status changes to Completed, this trigger automatically creates a bill entry if one doesn't already exist. Ensures no completed visit goes unbilled.

---

## Stored Procedures

### `view_doctor_data(in_username, in_password)`
Authenticates a doctor using credentials from `doctor_credentials`, retrieves their role and department, then returns filtered patient data. Seniors see all patients in their department; all other roles see only their own patients.

```sql
CALL view_doctor_data('doctor4', 'ic0pFSn0');
```

### `sp_monthlyrevenue(p_year, p_month)`
Calculates total billing revenue per department for a given calendar month. Joins bills through appointments, doctors, and departments, then groups and sums by department name.

```sql
CALL sp_monthlyrevenue(2025, 5);
```

### `sp_search_patient(search_term)`
Searches patients by name or phone number using partial matching with LIKE. Returns patient ID, name, date of birth, gender, and phone.

```sql
CALL sp_search_patient('Patient 1');
```

### `sp_patient_history(p_patientid)`
Returns the complete clinical journey of a patient — all appointments, prescriptions, lab results, bill amounts, and payment status in one result set ordered by most recent first.

```sql
CALL sp_patient_history(1);
```

### `sp_doctor_schedule(p_doctorid, p_start, p_end)`
Retrieves a doctor's appointment schedule for a given date range. Shows appointment time, status, patient name, phone, and gender.

```sql
CALL sp_doctor_schedule(1, '2024-01-01', '2025-12-31');
```

### `sp_cancel_appointment(p_appointmentid)`
Safely cancels an appointment with validation. Rejects the operation if the appointment doesn't exist, is already completed, or is already cancelled. Returns a success message on valid cancellation.

```sql
CALL sp_cancel_appointment(100);
```

### `sp_outstanding_bills()`
Generates a department-level summary of all unpaid bills. Shows count of unpaid bills, total outstanding amount, average bill amount, and the oldest unpaid date per department.

```sql
CALL sp_outstanding_bills();
```

### `sp_yearly_revenue(p_year)`
Annual revenue report by department. Breaks down total billed, collected, and pending amounts with a collection rate percentage for the specified year.

```sql
CALL sp_yearly_revenue(2024);
```

### `sp_abnormal_lab_reports()`
Parses JSON lab report data using `JSON_EXTRACT` and flags patients with out-of-range values — Low WBC (<4000), High WBC (>11000), Low Hemoglobin (<12.0), or Low RBC (<4.0). Returns patient details, doctor name, the actual values, and the specific flag reason.

```sql
CALL sp_abnormal_lab_reports();
```

---

## Views

### `vw_unpaid_bills`
All unpaid bills with patient name, phone, doctor name, department, amount, and bill date. Used by the billing team for daily collections follow-up.

### `vw_doctor_workload`
Each doctor's appointment statistics broken down by Completed, Scheduled, and Cancelled counts. Includes specialization, role, and department.

### `vw_patient_profile`
Patient demographics with calculated age, total visit count, last visit date, and total outstanding balance. Useful for reception and front desk lookups.

### `vw_department_dashboard`
Department-level KPIs: doctor count, total appointments, completion rate percentage, cancellation rate percentage, total revenue, collected revenue, and pending revenue.

### `vw_todays_appointments`
Today's scheduled appointments showing patient name, phone, doctor name, specialization, department, and time. Built for the front desk daily view.

```sql
SELECT * FROM vw_unpaid_bills;
SELECT * FROM vw_doctor_workload ORDER BY total_appointments DESC;
SELECT * FROM vw_patient_profile WHERE outstanding_balance > 0;
SELECT * FROM vw_department_dashboard ORDER BY total_revenue DESC;
SELECT * FROM vw_todays_appointments;
```

---

## Analytical Queries

Eleven standalone queries included in the SQL file for business intelligence and operational reporting.

| # | Query | What it reveals |
|---|---|---|
| 1 | Top 10 Busiest Doctors | Doctors ranked by completed appointments |
| 2 | Most Prescribed Medications | Prescription frequency with doctor and patient counts |
| 3 | Cancellation Rate by Specialization | Which specializations have the highest cancellation % |
| 4 | Revenue by Specialization | Total, average, max, and min bill per specialization |
| 5 | Patient Age Distribution | Age groups (Under 18 to Above 60) with gender breakdown |
| 6 | Monthly Appointment Trends | Month-by-month completed vs cancelled over the full period |
| 7 | Highest Outstanding Balances | Top 15 patients by total unpaid bill amount |
| 8 | Doctors with Highest Cancellation Rates | Doctors with >= 5 appointments ranked by cancellation % |
| 9 | Doctor Role Distribution per Department | Seniors, Juniors, Consultants, Residents per department |
| 10 | Average Revenue per Doctor by Role | Revenue generated per doctor grouped by role level |
| 11 | Prescription Patterns by Specialization | Which medications each specialization prescribes most |
| — | Repeat Patients | Patients with > 3 visits and how many doctors they've seen |
| — | Bill Collection Summary | Overall paid/unpaid counts, amounts, and collection rate % |

---

## Role-Based Access Control

The `doctor_credentials` table (sourced from `doctor_credentials.csv`) stores 200 doctor login entries:

| Column | Description |
|---|---|
| `doctor_id` | Maps to `doctors.doctorid` |
| `user_name` | Login handle (e.g., `doctor1` … `doctor200`) |
| `password` | Plaintext credential (8 characters) |

> **Security Note**: Passwords are stored in plaintext. Production systems should use bcrypt/Argon2 hashing with salting. The current design is suitable for academic/prototype contexts only.

Authentication is handled inside `view_doctor_data` via a `SELECT ... WHERE user_name = ? AND password = ?` pattern.

---

## Data Snapshot

| Entity | Count |
|---|---|
| Departments | 10 |
| Doctors | 200 |
| Patients | 2,000 |
| Appointments | 4,000 |
| Prescriptions | 3,000 |
| Bills | 3,500 |
| Lab Reports | 2,000 |
| Doctor Credentials | 200 |

**Revenue Summary**:
- Total Billed: **₹88,96,662.62**
- Total Collected (Paid): **₹61,26,315.40**
- Outstanding (Unpaid): **₹27,70,347.22**
- Average Bill: **₹2,541.90**
- Bill Range: ₹100.54 – ₹4,998.03

**Appointment Status**:
- Completed: 69.5% (2,779)
- Scheduled: 20.6% (823)
- Cancelled: 10.0% (398)

---

## Business Problems Solved

### 1. Scheduling Conflict Prevention
Two triggers (`check_new_appointment` on INSERT, `check_appointment_update` on UPDATE) prevent double-booking of doctors on both new bookings and rescheduling.

### 2. Role-Gated Clinical Data Access
The `view_doctor_data` procedure ensures junior staff can only view their own patient records while senior doctors can oversee their entire department.

### 3. Outstanding Payments Tracking
The `vw_unpaid_bills` view, `sp_outstanding_bills` procedure, and highest-balance analytical query give the billing team instant visibility into overdue amounts.

### 4. Auto-Billing on Completion
The `auto_bill_on_completion` trigger automatically creates a bill when an appointment is marked Completed, eliminating missed billing.

### 5. Patient Data Quality
Phone number validation triggers on both INSERT and UPDATE ensure all patient phone numbers are exactly 10 numeric digits.

### 6. Staff Record Protection
The `prevent_doctor_delete` trigger blocks accidental deletion of doctors who have upcoming scheduled appointments.

### 7. Patient Journey Reconstruction
The `sp_patient_history` procedure reconstructs any patient's full care history — visits, medications, lab results, and invoices — in a single call.

### 8. Clinical Alert — Abnormal Lab Values
The `sp_abnormal_lab_reports` procedure parses JSON lab data and flags patients with out-of-range WBC, RBC, or Hemoglobin values for early clinical intervention.

### 9. Department Performance Monitoring
The `vw_department_dashboard` view gives management instant KPIs per department — completion rate, cancellation rate, and revenue breakdown.

### 10. Revenue Reporting
`sp_monthlyrevenue` and `sp_yearly_revenue` provide monthly and annual revenue reports by department with collection rate tracking.

---

## Setup & Usage

```sql
-- 1. Create and select the database
CREATE DATABASE ehias;
USE ehias;

-- 2. Run the full schema creation script
SOURCE hospital_database.sql;

-- 3. Import the flat CSV as hospital_data table, then run insertion queries

-- 4. Test role-based access
CALL view_doctor_data('doctor1', 'W3jzIANG');

-- 5. Test revenue reports
CALL sp_monthlyrevenue(2025, 3);
CALL sp_yearly_revenue(2024);

-- 6. Search and view patient history
CALL sp_search_patient('Patient 1');
CALL sp_patient_history(1);

-- 7. Check abnormal lab reports
CALL sp_abnormal_lab_reports();

-- 8. View department dashboard
SELECT * FROM vw_department_dashboard;

-- 9. Check outstanding bills
CALL sp_outstanding_bills();
SELECT * FROM vw_unpaid_bills;
```
