from flask import Flask, render_template, request, redirect, url_for, flash
from db import query, call_procedure, execute
from datetime import datetime, date
from decimal import Decimal

app = Flask(__name__)
app.secret_key = 'ehias-hospital-dbms'

# ---------------------------------------------------------------------------
# Table metadata — drives generic CRUD routes and form rendering
# ---------------------------------------------------------------------------

TABLES = {
    'departments': {
        'pk': 'departmentid',
        'display_name': 'Departments',
        'columns': [
            ('departmentid', 'ID'),
            ('name', 'Name'),
        ],
        'fields': [
            {'name': 'name', 'label': 'Department Name', 'type': 'text',
             'required': True, 'maxlength': 50},
        ],
    },
    'doctors': {
        'pk': 'doctorid',
        'display_name': 'Doctors',
        'columns': [
            ('doctorid', 'ID'),
            ('name', 'Name'),
            ('specialization', 'Specialization'),
            ('role', 'Role'),
            ('departmentid', 'Dept ID'),
        ],
        'fields': [
            {'name': 'name', 'label': 'Name', 'type': 'text', 'maxlength': 50},
            {'name': 'specialization', 'label': 'Specialization', 'type': 'select',
             'options': ['Cardiology', 'Neurology', 'Oncology', 'Orthopedics',
                         'Pediatrics', 'Psychiatry', 'Radiology', 'Dermatology',
                         'ENT', 'General']},
            {'name': 'role', 'label': 'Role', 'type': 'select',
             'options': ['Senior', 'Junior', 'Consultant', 'Resident']},
            {'name': 'departmentid', 'label': 'Department', 'type': 'fk',
             'fk_table': 'departments', 'fk_id': 'departmentid',
             'fk_display': 'name'},
        ],
    },
    'patients': {
        'pk': 'patientid',
        'display_name': 'Patients',
        'columns': [
            ('patientid', 'ID'),
            ('name', 'Name'),
            ('dateofbirth', 'Date of Birth'),
            ('gender', 'Gender'),
            ('phone', 'Phone'),
        ],
        'fields': [
            {'name': 'name', 'label': 'Name', 'type': 'text', 'maxlength': 50},
            {'name': 'dateofbirth', 'label': 'Date of Birth', 'type': 'date'},
            {'name': 'gender', 'label': 'Gender', 'type': 'select',
             'options': ['m', 'f', 'o']},
            {'name': 'phone', 'label': 'Phone (10 digits)', 'type': 'text',
             'maxlength': 10},
        ],
    },
    'appointments': {
        'pk': 'appointmentid',
        'display_name': 'Appointments',
        'columns': [
            ('appointmentid', 'ID'),
            ('patientid', 'Patient ID'),
            ('doctorid', 'Doctor ID'),
            ('appointmenttime', 'Time'),
            ('status', 'Status'),
        ],
        'fields': [
            {'name': 'patientid', 'label': 'Patient ID', 'type': 'number'},
            {'name': 'doctorid', 'label': 'Doctor', 'type': 'fk',
             'fk_table': 'doctors', 'fk_id': 'doctorid', 'fk_display': 'name'},
            {'name': 'appointmenttime', 'label': 'Appointment Time',
             'type': 'datetime-local'},
            {'name': 'status', 'label': 'Status', 'type': 'select',
             'options': ['Scheduled', 'Completed', 'Cancelled']},
        ],
    },
    'prescriptions': {
        'pk': 'prescriptionid',
        'display_name': 'Prescriptions',
        'columns': [
            ('prescriptionid', 'ID'),
            ('appointmentid', 'Appt ID'),
            ('medication', 'Medication'),
            ('dosage', 'Dosage'),
        ],
        'fields': [
            {'name': 'appointmentid', 'label': 'Appointment ID', 'type': 'number'},
            {'name': 'medication', 'label': 'Medication', 'type': 'text',
             'maxlength': 50},
            {'name': 'dosage', 'label': 'Dosage', 'type': 'text', 'maxlength': 50},
        ],
    },
    'bills': {
        'pk': 'billid',
        'display_name': 'Bills',
        'columns': [
            ('billid', 'ID'),
            ('appointmentid', 'Appt ID'),
            ('amount', 'Amount'),
            ('paid', 'Paid'),
            ('billdate', 'Bill Date'),
        ],
        'fields': [
            {'name': 'appointmentid', 'label': 'Appointment ID', 'type': 'number'},
            {'name': 'amount', 'label': 'Amount', 'type': 'number', 'step': '0.01'},
            {'name': 'paid', 'label': 'Paid', 'type': 'select',
             'options': [{'value': '0', 'label': 'Unpaid'},
                         {'value': '1', 'label': 'Paid'}]},
            {'name': 'billdate', 'label': 'Bill Date', 'type': 'datetime-local'},
        ],
    },
    'labreports': {
        'pk': 'reportid',
        'display_name': 'Lab Reports',
        'columns': [
            ('reportid', 'ID'),
            ('appointmentid', 'Appt ID'),
            ('amount', 'Amount'),
            ('reportdata', 'Report Data'),
            ('createdate', 'Created'),
        ],
        'fields': [
            {'name': 'appointmentid', 'label': 'Appointment ID', 'type': 'number'},
            {'name': 'amount', 'label': 'Amount', 'type': 'number', 'step': '0.01'},
            {'name': 'reportdata', 'label': 'Report Data (JSON)', 'type': 'textarea'},
            {'name': 'createdate', 'label': 'Created Date', 'type': 'datetime-local'},
        ],
    },
}

# ---------------------------------------------------------------------------
# View metadata
# ---------------------------------------------------------------------------

VIEWS = {
    'vw_unpaid_bills': {
        'display_name': 'Unpaid Bills',
        'description': 'All unpaid bills with patient and doctor details',
    },
    'vw_doctor_workload': {
        'display_name': 'Doctor Workload',
        'description': 'Appointment counts per doctor split by status',
        'order_by': 'total_appointments DESC',
    },
    'vw_patient_profile': {
        'display_name': 'Patient Profiles',
        'description': 'Patient demographics with age, visit count, and balance',
        'order_by': 'total_visits DESC',
    },
    'vw_department_dashboard': {
        'display_name': 'Department Dashboard',
        'description': 'Department KPIs: completion rate, cancellation rate, revenue',
        'order_by': 'total_revenue DESC',
    },
    'vw_todays_appointments': {
        'display_name': "Today's Appointments",
        'description': "Today's scheduled appointments for the front desk",
    },
}

# ---------------------------------------------------------------------------
# Stored procedure metadata
# ---------------------------------------------------------------------------

PROCEDURES = {
    'sp_search_patient': {
        'display_name': 'Search Patient',
        'description': 'Search patients by name or phone number',
        'params': [
            {'name': 'search_term', 'label': 'Search Term', 'type': 'text',
             'placeholder': 'Patient name or phone'},
        ],
    },
    'sp_patient_history': {
        'display_name': 'Patient History',
        'description': 'Full clinical history: visits, prescriptions, labs, bills',
        'params': [
            {'name': 'patient_id', 'label': 'Patient ID', 'type': 'number',
             'placeholder': '1'},
        ],
    },
    'sp_doctor_schedule': {
        'display_name': 'Doctor Schedule',
        'description': "Doctor's appointment schedule for a date range",
        'params': [
            {'name': 'doctor_id', 'label': 'Doctor ID', 'type': 'number',
             'placeholder': '1'},
            {'name': 'start_date', 'label': 'Start Date', 'type': 'date'},
            {'name': 'end_date', 'label': 'End Date', 'type': 'date'},
        ],
    },
    'sp_cancel_appointment': {
        'display_name': 'Cancel Appointment',
        'description': 'Cancel a scheduled appointment with status validation',
        'params': [
            {'name': 'appointment_id', 'label': 'Appointment ID', 'type': 'number',
             'placeholder': '100'},
        ],
    },
    'sp_monthlyrevenue': {
        'display_name': 'Monthly Revenue',
        'description': 'Department-wise revenue for a given month',
        'params': [
            {'name': 'year', 'label': 'Year', 'type': 'number',
             'placeholder': '2025'},
            {'name': 'month', 'label': 'Month (1-12)', 'type': 'number',
             'placeholder': '5'},
        ],
    },
    'sp_yearly_revenue': {
        'display_name': 'Yearly Revenue',
        'description': 'Annual revenue by department with collection rate',
        'params': [
            {'name': 'year', 'label': 'Year', 'type': 'number',
             'placeholder': '2024'},
        ],
    },
    'sp_outstanding_bills': {
        'display_name': 'Outstanding Bills',
        'description': 'Unpaid bills summary grouped by department',
        'params': [],
    },
    'sp_abnormal_lab_reports': {
        'display_name': 'Abnormal Lab Reports',
        'description': 'Lab reports with out-of-range WBC, RBC, or Hemoglobin',
        'params': [],
    },
    'view_doctor_data': {
        'display_name': 'Doctor Data (Role-Based)',
        'description': 'Patient data filtered by doctor role after authentication',
        'params': [
            {'name': 'username', 'label': 'Username', 'type': 'text',
             'placeholder': 'doctor1'},
            {'name': 'password', 'label': 'Password', 'type': 'text',
             'placeholder': 'password'},
        ],
    },
}

# ---------------------------------------------------------------------------
# Analytical queries
# ---------------------------------------------------------------------------

ANALYTICS = [
    {
        'id': 'busiest_doctors',
        'title': 'Top 10 Busiest Doctors',
        'description': 'Doctors ranked by completed appointments',
        'sql': """
            SELECT d.doctorid, d.name, d.specialization, d.role,
                dep.name AS department,
                COUNT(a.appointmentid) AS completed_appointments
            FROM doctors d
                INNER JOIN departments dep ON dep.departmentid = d.departmentid
                INNER JOIN appointments a ON a.doctorid = d.doctorid
            WHERE a.status = 'Completed'
            GROUP BY d.doctorid, d.name, d.specialization, d.role, dep.name
            ORDER BY completed_appointments DESC
            LIMIT 10
        """,
    },
    {
        'id': 'most_prescribed',
        'title': 'Most Prescribed Medications',
        'description': 'Prescription frequency with doctor and patient counts',
        'sql': """
            SELECT pr.medication,
                COUNT(*) AS times_prescribed,
                COUNT(DISTINCT a.doctorid) AS prescribed_by_doctors,
                COUNT(DISTINCT a.patientid) AS given_to_patients
            FROM prescriptions pr
                INNER JOIN appointments a ON a.appointmentid = pr.appointmentid
            GROUP BY pr.medication
            ORDER BY times_prescribed DESC
        """,
    },
    {
        'id': 'cancellation_by_spec',
        'title': 'Cancellation Rate by Specialization',
        'description': 'Which specializations have the highest cancellation percentage',
        'sql': """
            SELECT d.specialization,
                COUNT(*) AS total,
                SUM(CASE WHEN a.status = 'Completed' THEN 1 ELSE 0 END) AS completed,
                SUM(CASE WHEN a.status = 'Scheduled' THEN 1 ELSE 0 END) AS scheduled,
                SUM(CASE WHEN a.status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
                ROUND(SUM(CASE WHEN a.status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0
                    / COUNT(*), 1) AS cancellation_pct
            FROM appointments a
                INNER JOIN doctors d ON d.doctorid = a.doctorid
            GROUP BY d.specialization
            ORDER BY total DESC
        """,
    },
    {
        'id': 'revenue_by_spec',
        'title': 'Revenue by Specialization',
        'description': 'Total, average, max, and min bill per specialization',
        'sql': """
            SELECT d.specialization,
                COUNT(b.billid) AS bill_count,
                SUM(b.amount) AS total_revenue,
                ROUND(AVG(b.amount), 2) AS avg_bill,
                MAX(b.amount) AS highest_bill,
                MIN(b.amount) AS lowest_bill
            FROM bills b
                INNER JOIN appointments a ON a.appointmentid = b.appointmentid
                INNER JOIN doctors d ON d.doctorid = a.doctorid
            GROUP BY d.specialization
            ORDER BY total_revenue DESC
        """,
    },
    {
        'id': 'age_distribution',
        'title': 'Patient Age Distribution',
        'description': 'Age groups with gender breakdown',
        'sql': """
            SELECT
                CASE
                    WHEN TIMESTAMPDIFF(YEAR, dateofbirth, CURDATE()) < 18 THEN 'Under 18'
                    WHEN TIMESTAMPDIFF(YEAR, dateofbirth, CURDATE()) BETWEEN 18 AND 30 THEN '18-30'
                    WHEN TIMESTAMPDIFF(YEAR, dateofbirth, CURDATE()) BETWEEN 31 AND 45 THEN '31-45'
                    WHEN TIMESTAMPDIFF(YEAR, dateofbirth, CURDATE()) BETWEEN 46 AND 60 THEN '46-60'
                    ELSE 'Above 60'
                END AS age_group,
                COUNT(*) AS patient_count,
                SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) AS male,
                SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) AS female,
                SUM(CASE WHEN gender = 'O' THEN 1 ELSE 0 END) AS other
            FROM patients
            GROUP BY age_group
            ORDER BY FIELD(age_group, 'Under 18', '18-30', '31-45', '46-60', 'Above 60')
        """,
    },
    {
        'id': 'monthly_trends',
        'title': 'Monthly Appointment Trends',
        'description': 'Month-by-month appointment counts with status breakdown',
        'sql': """
            SELECT YEAR(appointmenttime) AS yr, MONTH(appointmenttime) AS mn,
                COUNT(*) AS total_appointments,
                SUM(CASE WHEN status = 'Completed' THEN 1 ELSE 0 END) AS completed,
                SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled
            FROM appointments
            GROUP BY YEAR(appointmenttime), MONTH(appointmenttime)
            ORDER BY yr, mn
        """,
    },
    {
        'id': 'highest_balances',
        'title': 'Highest Outstanding Balances',
        'description': 'Top 15 patients by total unpaid bill amount',
        'sql': """
            SELECT p.patientid, p.name, p.phone,
                COUNT(b.billid) AS unpaid_bills,
                SUM(b.amount) AS total_outstanding
            FROM patients p
                INNER JOIN appointments a ON a.patientid = p.patientid
                INNER JOIN bills b ON b.appointmentid = a.appointmentid
            WHERE b.paid = 0
            GROUP BY p.patientid, p.name, p.phone
            ORDER BY total_outstanding DESC
            LIMIT 15
        """,
    },
    {
        'id': 'doctor_cancellation_rates',
        'title': 'Doctors with Highest Cancellation Rates',
        'description': 'Doctors with at least 5 appointments ranked by cancellation %',
        'sql': """
            SELECT d.doctorid, d.name, d.specialization,
                COUNT(*) AS total_appointments,
                SUM(CASE WHEN a.status = 'Cancelled' THEN 1 ELSE 0 END) AS cancellations,
                ROUND(SUM(CASE WHEN a.status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0
                    / COUNT(*), 1) AS cancellation_pct
            FROM doctors d
                INNER JOIN appointments a ON a.doctorid = d.doctorid
            GROUP BY d.doctorid, d.name, d.specialization
            HAVING COUNT(*) >= 5
            ORDER BY cancellation_pct DESC
            LIMIT 10
        """,
    },
    {
        'id': 'role_distribution',
        'title': 'Doctor Role Distribution per Department',
        'description': 'Seniors, Juniors, Consultants, Residents per department',
        'sql': """
            SELECT dep.name AS department,
                SUM(CASE WHEN d.role = 'Senior' THEN 1 ELSE 0 END) AS seniors,
                SUM(CASE WHEN d.role = 'Junior' THEN 1 ELSE 0 END) AS juniors,
                SUM(CASE WHEN d.role = 'Consultant' THEN 1 ELSE 0 END) AS consultants,
                SUM(CASE WHEN d.role = 'Resident' THEN 1 ELSE 0 END) AS residents,
                COUNT(*) AS total_doctors
            FROM doctors d
                INNER JOIN departments dep ON dep.departmentid = d.departmentid
            GROUP BY dep.name
            ORDER BY total_doctors DESC
        """,
    },
    {
        'id': 'avg_revenue_by_role',
        'title': 'Average Revenue per Doctor by Role',
        'description': 'Revenue generated per doctor grouped by role level',
        'sql': """
            SELECT d.role,
                COUNT(DISTINCT d.doctorid) AS doctor_count,
                ROUND(SUM(b.amount) / COUNT(DISTINCT d.doctorid), 2) AS avg_revenue_per_doctor,
                ROUND(AVG(b.amount), 2) AS avg_bill_amount
            FROM doctors d
                INNER JOIN appointments a ON a.doctorid = d.doctorid
                INNER JOIN bills b ON b.appointmentid = a.appointmentid
            GROUP BY d.role
            ORDER BY avg_revenue_per_doctor DESC
        """,
    },
    {
        'id': 'prescription_patterns',
        'title': 'Prescription Patterns by Specialization',
        'description': 'Which medications each specialization prescribes most',
        'sql': """
            SELECT d.specialization, pr.medication,
                COUNT(*) AS prescription_count
            FROM prescriptions pr
                INNER JOIN appointments a ON a.appointmentid = pr.appointmentid
                INNER JOIN doctors d ON d.doctorid = a.doctorid
            GROUP BY d.specialization, pr.medication
            ORDER BY d.specialization, prescription_count DESC
        """,
    },
    {
        'id': 'repeat_patients',
        'title': 'Repeat Patients',
        'description': 'Patients with more than 3 visits and how many doctors seen',
        'sql': """
            SELECT p.patientid, p.name, p.phone, p.gender,
                COUNT(a.appointmentid) AS visit_count,
                COUNT(DISTINCT a.doctorid) AS doctors_seen,
                MIN(a.appointmenttime) AS first_visit,
                MAX(a.appointmenttime) AS latest_visit
            FROM patients p
                INNER JOIN appointments a ON a.patientid = p.patientid
            GROUP BY p.patientid, p.name, p.phone, p.gender
            HAVING visit_count > 3
            ORDER BY visit_count DESC
        """,
    },
    {
        'id': 'bill_collection_summary',
        'title': 'Overall Bill Collection Summary',
        'description': 'Total paid/unpaid counts, amounts, and collection rate',
        'sql': """
            SELECT
                COUNT(*) AS total_bills,
                SUM(CASE WHEN paid = 1 THEN 1 ELSE 0 END) AS paid_count,
                SUM(CASE WHEN paid = 0 THEN 1 ELSE 0 END) AS unpaid_count,
                SUM(amount) AS total_billed,
                SUM(CASE WHEN paid = 1 THEN amount ELSE 0 END) AS total_collected,
                SUM(CASE WHEN paid = 0 THEN amount ELSE 0 END) AS total_pending,
                ROUND(SUM(CASE WHEN paid = 1 THEN amount ELSE 0 END) * 100.0
                    / SUM(amount), 1) AS collection_rate_pct
            FROM bills
        """,
    },
]

# ---------------------------------------------------------------------------
# Template filters
# ---------------------------------------------------------------------------


@app.template_filter('fmt')
def format_value(value):
    if value is None:
        return ''
    if isinstance(value, datetime):
        return value.strftime('%Y-%m-%d %H:%M')
    if isinstance(value, date):
        return value.strftime('%Y-%m-%d')
    if isinstance(value, Decimal):
        return f'{value:,.2f}'
    return value


@app.template_filter('datetime_local')
def datetime_local_filter(value):
    if isinstance(value, datetime):
        return value.strftime('%Y-%m-%dT%H:%M')
    if isinstance(value, date):
        return value.strftime('%Y-%m-%d')
    return value or ''


@app.template_filter('date_input')
def date_input_filter(value):
    if isinstance(value, (date, datetime)):
        return value.strftime('%Y-%m-%d')
    return value or ''


# ---------------------------------------------------------------------------
# Context processor — makes nav data available in every template
# ---------------------------------------------------------------------------


@app.context_processor
def inject_nav():
    return {'nav_tables': TABLES, 'nav_views': VIEWS}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_fk_options(fields):
    options = {}
    for f in fields:
        if f['type'] != 'fk':
            continue
        rows = query(
            f"SELECT {f['fk_id']}, {f['fk_display']} "
            f"FROM {f['fk_table']} ORDER BY {f['fk_id']}"
        )
        options[f['name']] = [
            {'id': r[f['fk_id']],
             'display': f"{r[f['fk_id']]} - {r[f['fk_display']]}"}
            for r in rows
        ]
    return options


def _form_values(fields):
    values = []
    for f in fields:
        raw = request.form.get(f['name'])
        if not raw:
            values.append(None)
        elif f['type'] == 'datetime-local':
            values.append(raw.replace('T', ' '))
        else:
            values.append(raw)
    return values


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------


@app.route('/')
def dashboard():
    try:
        dept = query(
            "SELECT * FROM vw_department_dashboard ORDER BY total_revenue DESC"
        )
        todays = query("SELECT * FROM vw_todays_appointments")
    except Exception as e:
        flash(str(e), 'danger')
        dept, todays = [], []
    return render_template(
        'dashboard.html', departments=dept, todays=todays, active_page='dashboard'
    )


# ---------------------------------------------------------------------------
# Generic CRUD
# ---------------------------------------------------------------------------


@app.route('/table/<table_name>')
def table_list(table_name):
    if table_name not in TABLES:
        flash('Table not found.', 'danger')
        return redirect(url_for('dashboard'))
    config = TABLES[table_name]
    try:
        data = query(f"SELECT * FROM {table_name}")
    except Exception as e:
        flash(str(e), 'danger')
        data = []
    return render_template(
        'table_list.html', table_name=table_name, config=config,
        data=data, active_page=table_name,
    )


@app.route('/table/<table_name>/add', methods=['GET', 'POST'])
def table_add(table_name):
    if table_name not in TABLES:
        flash('Table not found.', 'danger')
        return redirect(url_for('dashboard'))
    config = TABLES[table_name]

    if request.method == 'POST':
        fields = config['fields']
        col_names = ', '.join(f['name'] for f in fields)
        placeholders = ', '.join(['%s'] * len(fields))
        try:
            execute(
                f"INSERT INTO {table_name} ({col_names}) VALUES ({placeholders})",
                _form_values(fields),
            )
            flash('Record added successfully.', 'success')
            return redirect(url_for('table_list', table_name=table_name))
        except Exception as e:
            flash(str(e), 'danger')

    return render_template(
        'table_form.html', table_name=table_name, config=config,
        record=None, fk_options=_load_fk_options(config['fields']),
        active_page=table_name,
    )


@app.route('/table/<table_name>/edit/<int:record_id>', methods=['GET', 'POST'])
def table_edit(table_name, record_id):
    if table_name not in TABLES:
        flash('Table not found.', 'danger')
        return redirect(url_for('dashboard'))
    config = TABLES[table_name]
    pk = config['pk']

    if request.method == 'POST':
        fields = config['fields']
        set_clause = ', '.join(f"{f['name']} = %s" for f in fields)
        vals = _form_values(fields)
        vals.append(record_id)
        try:
            execute(
                f"UPDATE {table_name} SET {set_clause} WHERE {pk} = %s", vals,
            )
            flash('Record updated successfully.', 'success')
            return redirect(url_for('table_list', table_name=table_name))
        except Exception as e:
            flash(str(e), 'danger')

    rows = query(f"SELECT * FROM {table_name} WHERE {pk} = %s", (record_id,))
    if not rows:
        flash('Record not found.', 'danger')
        return redirect(url_for('table_list', table_name=table_name))

    return render_template(
        'table_form.html', table_name=table_name, config=config,
        record=rows[0], fk_options=_load_fk_options(config['fields']),
        active_page=table_name,
    )


@app.route('/table/<table_name>/delete/<int:record_id>', methods=['POST'])
def table_delete(table_name, record_id):
    if table_name not in TABLES:
        flash('Table not found.', 'danger')
        return redirect(url_for('dashboard'))
    pk = TABLES[table_name]['pk']
    try:
        execute(f"DELETE FROM {table_name} WHERE {pk} = %s", (record_id,))
        flash('Record deleted.', 'success')
    except Exception as e:
        flash(str(e), 'danger')
    return redirect(url_for('table_list', table_name=table_name))


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------


@app.route('/view/<view_name>')
def view_data(view_name):
    if view_name not in VIEWS:
        flash('View not found.', 'danger')
        return redirect(url_for('dashboard'))
    cfg = VIEWS[view_name]
    order = f" ORDER BY {cfg['order_by']}" if 'order_by' in cfg else ''
    try:
        data = query(f"SELECT * FROM {view_name}{order}")
    except Exception as e:
        flash(str(e), 'danger')
        data = []
    return render_template(
        'results.html', title=cfg['display_name'],
        description=cfg['description'], data=data,
        form_fields=None, active_page=view_name,
    )


# ---------------------------------------------------------------------------
# Stored procedures
# ---------------------------------------------------------------------------


@app.route('/procedures')
def procedures_list():
    return render_template(
        'procedures.html', procedures=PROCEDURES, active_page='procedures',
    )


@app.route('/procedure/<proc_name>', methods=['GET', 'POST'])
def procedure_exec(proc_name):
    if proc_name not in PROCEDURES:
        flash('Procedure not found.', 'danger')
        return redirect(url_for('procedures_list'))

    cfg = PROCEDURES[proc_name]
    data = None
    param_defs = cfg.get('params', [])

    if not param_defs:
        try:
            data = call_procedure(proc_name)
        except Exception as e:
            flash(str(e), 'danger')
            data = []
        return render_template(
            'results.html', title=cfg['display_name'],
            description=cfg['description'], data=data,
            form_fields=None, active_page='procedures',
        )

    if request.method == 'POST':
        params = []
        for p in param_defs:
            val = request.form.get(p['name'], '')
            if p['type'] == 'number' and val:
                params.append(int(val))
            else:
                params.append(val)
        try:
            data = call_procedure(proc_name, params)
        except Exception as e:
            flash(str(e), 'danger')
            data = []

    form_fields = [
        {**p, 'value': request.form.get(p['name'], '') if request.method == 'POST' else ''}
        for p in param_defs
    ]
    return render_template(
        'results.html', title=cfg['display_name'],
        description=cfg['description'], data=data,
        form_fields=form_fields, active_page='procedures',
    )


# ---------------------------------------------------------------------------
# Analytics
# ---------------------------------------------------------------------------


@app.route('/analytics')
def analytics_list():
    return render_template(
        'analytics.html', analytics=ANALYTICS, active_page='analytics',
    )


@app.route('/analytics/<query_id>')
def analytics_query(query_id):
    item = next((a for a in ANALYTICS if a['id'] == query_id), None)
    if not item:
        flash('Query not found.', 'danger')
        return redirect(url_for('analytics_list'))
    try:
        data = query(item['sql'])
    except Exception as e:
        flash(str(e), 'danger')
        data = []
    return render_template(
        'results.html', title=item['title'],
        description=item['description'], data=data,
        form_fields=None, active_page='analytics',
    )


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    app.run(debug=True, port=5000)
