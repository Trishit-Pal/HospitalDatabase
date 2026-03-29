# 🏥 EHIAS — Electronic Hospital Information & Appointment System

> A relational MySQL database designed to manage end-to-end hospital operations: patient records, doctor scheduling, prescriptions, billing, and diagnostic lab reports — secured with role-based access control.

---

## 📌 Table of Contents

- [Overview](#overview)
- [Database Architecture](#database-architecture)
- [Schema — Table Definitions](#schema--table-definitions)
- [Entity Relationship Summary](#entity-relationship-summary)
- [Stored Procedures](#stored-procedures)
- [Triggers](#triggers)
- [Role-Based Access Control](#role-based-access-control)
- [Data Snapshot](#data-snapshot)
- [Business Problems Solved](#business-problems-solved)
- [Setup & Usage](#setup--usage)

---

## Overview

**EHIAS** (Electronic Hospital Information & Appointment System) is a normalized MySQL relational database that models the operational core of a mid-to-large hospital system. It manages 10 entities across departments, medical professionals, patient care pathways, revenue cycles, and diagnostic workflows.

The system was populated from a denormalized flat-file export (`hospital_data_10000_rows.csv`) containing 10,000 rows of synthetic patient and operational records, and authenticated via a separate `doctor_credentials.csv` file listing 200 doctor login accounts.

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
├── labreports           ← Diagnostic test results per appointment
├── bills                ← Financial records per appointment
│
└── doctor_credentials   ← Authentication table (external CSV source)
```

### Design Principles

- **3NF Normalization**: The flat CSV source was decomposed into 7 normalized tables eliminating all repeating groups and transitive dependencies.
- **Referential Integrity**: All inter-table relationships are enforced via `FOREIGN KEY` constraints.
- **Appointment as Central Hub**: The `appointments` table acts as the system's pivot — every clinical and financial event (prescription, lab report, bill) traces back to a single appointment record.
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

**Doctor Roles**: `Senior`, `Consultant`, `Resident`, `Junior`

**Specializations available**: Cardiology, Neurology, Oncology, Orthopedics, Pediatrics, Psychiatry, Radiology, Dermatology, ENT, General

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

**Top medications in dataset**: Painkiller, Cough Syrup, Insulin, Ibuprofen, Antibiotics, Vitamin D, Amoxicillin, Paracetamol

---

### `bills`
Financial records per appointment, tracking amounts and payment status.

| Column | Type | Constraints |
|---|---|---|
| `billid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `appointmentid` | INT | FK → `appointments.appointmentid` |
| `amount` | DECIMAL(10,2) | — |
| `paid` | TINYINT(1) | — (0 = unpaid, 1 = paid) |
| `billdate` | DATETIME | DEFAULT CURRENT_TIMESTAMP |

---

### `labreports`
Diagnostic test results stored as JSON text, linked per appointment.

| Column | Type | Constraints |
|---|---|---|
| `reportid` | INT | PRIMARY KEY, AUTO_INCREMENT |
| `appointmentid` | INT | FK → `appointments.appointmentid` |
| `amount` | DECIMAL(10,2) | — |
| `reportdata` | TEXT | JSON structure: WBC, RBC, Hemoglobin |
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

## Stored Procedures

### `view_doctor_data(in_username, in_password)`

**Purpose**: Role-based patient data viewer with authentication. Doctors log in with credentials; the procedure returns filtered patient data based on their role level.

**Logic Flow**:

```
1. Validate username + password against doctor_credentials
2. Retrieve the doctor's role and department
3. IF role = 'Senior':
       → Return all patients in the same department (cross-doctor view)
   ELSE (Resident / Consultant / Junior):
       → Return only patients booked with this specific doctor
```

**Access levels**:
- `Senior` → Department-wide view: all patients, appointments, prescriptions, lab reports in their department
- `Non-Senior` → Personal view: only appointments assigned to the logged-in doctor

**Usage**:
```sql
CALL view_doctor_data('doctor2', 'lBYqWawB');
CALL view_doctor_data('doctor4', 'ic0pFSn0');
```

---

### `sp_monthlyrevenue(p_year INT, p_month INT)`

**Purpose**: Calculates total billing revenue per department for a given calendar month.

**Logic**: Joins `bills → appointments → doctors → departments`, groups by department name, and sums paid + unpaid bill amounts for the specified year-month.


**Usage**:
```sql
CALL sp_monthlyrevenue(2025, 5);
```

---

## Triggers

### `check_new_appointment` (BEFORE INSERT on `appointments`)

Validates every new appointment insert against two business rules:

**Rule 1 — No Past Appointments**
```
IF appointmenttime < NOW() THEN
    SIGNAL SQLSTATE '49000' → 'Error: Appointment cannot be in the past'
```

**Rule 2 — No Double-Booking**
```
IF a 'Scheduled' appointment already exists for the same doctor at the same time THEN
    SIGNAL SQLSTATE '45000' → 'Error: Doctor already has an appointment at this time.'
```

This prevents ghost bookings and scheduling conflicts without application-layer enforcement.

---

## Role-Based Access Control

The `doctor_credentials` table (sourced from `doctor_credentials.csv`) stores 200 doctor login entries:

| Column | Description |
|---|---|
| `doctor_id` | Maps to `doctors.doctorid` |
| `user_name` | Login handle (e.g., `doctor1` … `doctor200`) |
| `password` | Plaintext credential (8 characters) |

> ⚠️ **Security Note**: Passwords are stored in **plaintext**. Production systems should use bcrypt/Argon2 hashing with salting. The current design is suitable for academic/prototype contexts only.

Authentication is handled inside `view_doctor_data` via a simple `SELECT ... WHERE user_name = ? AND password = ?` pattern.

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
The `check_new_appointment` trigger prevents double-booking of doctors, reducing scheduling errors at the database level before any application logic runs.

### 2. Role-Gated Clinical Data Access
The `view_doctor_data` procedure ensures junior staff can only view their own patient records while senior doctors can oversee their entire department — enforcing clinical data privacy at the database layer.

### 3. Monthly Departmental Revenue Reporting
The `sp_monthlyrevenue` procedure enables finance teams to pull department-wise revenue summaries for any given month, supporting billing cycle reporting and budgetary review.

### 4. Outstanding Payments Tracking
The `bills.paid` flag (TINYINT boolean) enables simple queries to isolate unpaid bills, enabling follow-up by the billing department.

### 5. Audit Trail for Clinical Events
All bills and lab reports carry auto-timestamped `billdate` / `createdate` columns, enabling audit queries over any time window without relying on application logs.

### 6. Patient Journey Reconstruction
Through the `appointments` hub table, any patient's full care history — doctor visits, medications, test results, and invoices — can be reconstructed in a single multi-join query.

---

## Setup & Usage

```sql
-- 1. Create and select the database
CREATE DATABASE ehias;
USE ehias;

-- 2. Run the full schema creation script
SOURCE hospital_database.sql;

-- 3. Import the flat CSV
-- (Load hospital_data_10000_rows.csv as the hospital_data table)

-- 4. Run insertion queries from the SQL script to populate normalized tables

-- 5. Test role-based access
CALL view_doctor_data('doctor1', 'W3jzIANG');

-- 6. Test revenue report
CALL sp_monthlyrevenue(2025, 3);
```

---

## Known Bugs & Improvement Areas

| Issue | Location | Recommendation |
|---|---|---|
| Incorrect join in revenue procedure | `sp_monthlyrevenue` | Change `d1.departmentid = d.doctorid` → `d1.departmentid = d.departmentid` |
| Plaintext passwords | `doctor_credentials` | Migrate to bcrypt hashing |
| SQLSTATE `49000` is non-standard | `check_new_appointment` trigger | Use `45000` (standard user-defined exception state) for both signals |
| `delimiter` missing semicolon at end | `sp_monthlyrevenue` | Change `delimiter` → `delimiter ;` |
| No index on appointment time | `appointments` | Add `INDEX idx_apt_time (appointmenttime)` for trigger performance |

---
