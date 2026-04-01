import mysql.connector
from mysql.connector import Error

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'ehias',
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def query(sql, params=None):
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(sql, params or ())
        return cursor.fetchall()
    finally:
        cursor.close()
        conn.close()


def execute(sql, params=None):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(sql, params or ())
        conn.commit()
        return cursor.lastrowid
    except Error:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()


def call_procedure(name, params=None):
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(name, params or ())
        results = []
        for result_set in cursor.stored_results():
            results.extend(result_set.fetchall())
        conn.commit()
        return results
    except Error:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
