#!/usr/bin/env python3
"""레거시 SQL 스크립트 분석 보고서 PDF 생성"""

from fpdf import FPDF
import os

class ReportPDF(FPDF):
    def header(self):
        self.set_font('Helvetica', 'B', 10)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, 'ACE Online - Legacy SQL Analysis Report', align='R', new_x="LMARGIN", new_y="NEXT")
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(3)

    def footer(self):
        self.set_y(-15)
        self.set_font('Helvetica', 'I', 8)
        self.set_text_color(150, 150, 150)
        self.cell(0, 10, f'Page {self.page_no()}/{{nb}}', align='C')

    def section_title(self, title, color=(30, 60, 120)):
        self.set_font('Helvetica', 'B', 14)
        self.set_text_color(*color)
        self.cell(0, 10, title, new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(*color)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(4)

    def sub_title(self, title, number=None):
        self.set_font('Helvetica', 'B', 11)
        self.set_text_color(50, 50, 50)
        prefix = f"{number}. " if number else ""
        self.cell(0, 8, f"{prefix}{title}", new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def body_text(self, text):
        self.set_font('Helvetica', '', 10)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5.5, text)
        self.ln(2)

    def code_block(self, code):
        self.set_font('Courier', '', 8)
        self.set_fill_color(245, 245, 245)
        self.set_text_color(60, 60, 60)
        x = self.get_x()
        self.set_x(x + 5)
        self.multi_cell(180, 4.5, code, fill=True)
        self.ln(3)

    def severity_badge(self, level, text):
        colors = {
            'critical': (220, 50, 50),
            'warning': (230, 150, 30),
            'info': (50, 130, 200),
        }
        r, g, b = colors.get(level, (100, 100, 100))
        self.set_font('Helvetica', 'B', 9)
        self.set_fill_color(r, g, b)
        self.set_text_color(255, 255, 255)
        w = self.get_string_width(text) + 8
        self.cell(w, 6, text, fill=True, align='C')
        self.cell(3, 6, '')  # spacer

    def bullet(self, text, indent=15):
        x = self.get_x()
        self.set_x(x + indent)
        self.set_font('Helvetica', '', 10)
        self.set_text_color(40, 40, 40)
        self.cell(4, 5.5, '-')
        self.multi_cell(170 - indent, 5.5, text)
        self.ln(1)

    def check_page_break(self, h=30):
        if self.get_y() + h > 270:
            self.add_page()


def generate_report():
    pdf = ReportPDF()
    pdf.alias_nb_pages()
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    # ==========================================
    # 표지
    # ==========================================
    pdf.ln(40)
    pdf.set_font('Helvetica', 'B', 28)
    pdf.set_text_color(30, 60, 120)
    pdf.cell(0, 15, 'Legacy SQL Script', align='C', new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 15, 'Analysis Report', align='C', new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)
    pdf.set_font('Helvetica', '', 14)
    pdf.set_text_color(100, 100, 100)
    pdf.cell(0, 10, 'ACE Online - Sales & Inventory System', align='C', new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    pdf.set_font('Helvetica', '', 11)
    pdf.cell(0, 8, 'Date: 2026-03-25', align='C', new_x="LMARGIN", new_y="NEXT")
    pdf.ln(30)

    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_text_color(50, 50, 50)
    pdf.cell(0, 8, 'Summary', align='C', new_x="LMARGIN", new_y="NEXT")
    pdf.ln(3)
    pdf.set_font('Helvetica', '', 10)
    pdf.set_text_color(70, 70, 70)
    pdf.multi_cell(0, 5.5,
        "This report analyzes the legacy SQL view scripts used in the current sales and inventory "
        "management system. It identifies 10 critical issues across performance, scalability, "
        "maintainability, and data integrity. Each issue includes severity assessment, "
        "impact analysis, and recommended improvements.",
        align='C'
    )

    # ==========================================
    # 1. Architecture Overview
    # ==========================================
    pdf.add_page()
    pdf.section_title('1. Current Architecture Overview')

    pdf.body_text(
        "The current system uses a chain of 7+ PostgreSQL views to calculate real-time "
        "inventory (stockreal). The calculation formula is:"
    )
    pdf.code_block("stockreal = ingreso + offset - venta - suspendido")

    pdf.body_text("View dependency chain:")
    pdf.code_block(
        "codigos (base table)\n"
        "  -> corregidodetails_id_2        (offset corrections)\n"
        "  -> itemdetails_id_2             (sales summary)\n"
        "  -> ingresodetails_id_2          (income summary)\n"
        "  -> itemdetails_today_id_2       (today's sales)\n"
        "  -> ingresodetails_today_id_2    (today's income)\n"
        "  -> cobdetalles_id_2             (suspended/reserved)\n"
        "     -> screendetails2_id_2       (combined view)\n"
        "        -> screendetails2_id      (per sucursal)\n"
        "        -> screendetails2_deposito_id_tmp\n"
        "           -> screendetails2_deposito_id  (warehouse)\n"
        "              -> screendetails2_deposito_total_id\n"
        "        -> screendetails2_total_id (grand total)"
    )

    pdf.body_text(
        "Each query to any final view triggers the entire chain, "
        "causing massive computational overhead as data grows."
    )

    # ==========================================
    # 2. Critical Issues
    # ==========================================
    pdf.add_page()
    pdf.section_title('2. Critical Issues', color=(200, 50, 50))

    # Issue 1
    pdf.check_page_break(60)
    pdf.severity_badge('critical', 'CRITICAL')
    pdf.ln(8)
    pdf.sub_title('Store-specific Hardcoded Views (_id_2 suffix)', 1)
    pdf.body_text(
        "All view names contain '_id_2' suffix, indicating they are created specifically "
        "for store_id=2. This means for 300 tiendas, you would need to create and maintain "
        "300 separate sets of views (approximately 3,600+ views total)."
    )
    pdf.code_block(
        "-- Current: One set per store\n"
        "CREATE VIEW screendetails2_id_2 AS ...  -- store 2 only\n"
        "CREATE VIEW screendetails2_id_3 AS ...  -- store 3 copy\n"
        "CREATE VIEW screendetails2_id_4 AS ...  -- store 4 copy\n"
        "-- ... x 300 stores = 3,600+ views"
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Replace with parameterized functions or a single view that includes store_id "
        "as a column, filtered at query time with WHERE clause."
    )
    pdf.code_block(
        "-- Improved: Single parameterized function\n"
        "CREATE FUNCTION get_screen_details(p_store_id INT, p_sucursal INT)\n"
        "RETURNS TABLE(...) AS $$ ... $$ LANGUAGE sql;"
    )

    # Issue 2
    pdf.check_page_break(60)
    pdf.severity_badge('critical', 'CRITICAL')
    pdf.ln(8)
    pdf.sub_title('7-Layer Nested View Chain (Performance)', 2)
    pdf.body_text(
        "The system chains 7+ views where each view depends on the previous one. "
        "PostgreSQL must execute the ENTIRE chain for every query to the final view. "
        "With 300 stores x 20,000 products = 6M products, each query triggers:\n"
        "- 6M rows through corregidodetails\n"
        "- 6M rows through itemdetails (with GROUP BY)\n"
        "- 6M rows through ingresodetails (with GROUP BY)\n"
        "- Multiple LEFT JOINs across all intermediate results\n\n"
        "Estimated query time: 10-30+ seconds per final view query."
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Use MATERIALIZED VIEWs with REFRESH CONCURRENTLY, or better yet, "
        "maintain a denormalized stock_summary table updated by triggers on "
        "INSERT/UPDATE/DELETE events."
    )

    # Issue 3
    pdf.check_page_break(60)
    pdf.severity_badge('critical', 'CRITICAL')
    pdf.ln(8)
    pdf.sub_title('Stock Calculated via View Chain (Data Integrity)', 3)
    pdf.body_text(
        "Real-time stock is calculated as:\n"
        "  stockreal = ingresosumcant + cntoffset - ventasumcant - suspendido_total\n\n"
        "This approach has critical risks:\n"
        "- Any missed record (ingreso, venta, corregido) corrupts stock permanently\n"
        "- No audit trail or reconciliation mechanism\n"
        "- Race conditions: two simultaneous sales can both read same stock\n"
        "- No constraint to prevent negative stock"
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Maintain a 'current_stock' column updated atomically via triggers or "
        "application-level transactions with row-level locking (SELECT ... FOR UPDATE). "
        "Use stock_movements table as the audit log."
    )
    pdf.code_block(
        "-- Atomic stock update with race condition prevention\n"
        "UPDATE products SET stock = stock - :qty\n"
        "WHERE id = :product_id AND stock >= :qty;\n"
        "-- Returns 0 rows affected if insufficient stock"
    )

    # Issue 4
    pdf.check_page_break(50)
    pdf.severity_badge('critical', 'CRITICAL')
    pdf.ln(8)
    pdf.sub_title('No Index Strategy', 4)
    pdf.body_text(
        "The script creates views with heavy JOIN and WHERE conditions but defines "
        "no indexes. Critical missing indexes:"
    )
    pdf.bullet("codigos.borrado (used in every WHERE clause)")
    pdf.bullet("vdetalle.ref_id_codigo + borrado + bfallado + bmovido (composite)")
    pdf.bullet("vdetalle.fecha1 (date filtering for today's views)")
    pdf.bullet("ingresos.ref_id_codigo + borrado + fecha (composite)")
    pdf.bullet("cobdetalles.ref_id_codigo + borrado")
    pdf.bullet("corregidos.ref_id_codigo + borrado")
    pdf.body_text(
        "Without these indexes, PostgreSQL performs sequential scans on every table "
        "for every query. With 300K+ daily events, this becomes catastrophic."
    )

    # Issue 5
    pdf.check_page_break(50)
    pdf.severity_badge('critical', 'CRITICAL')
    pdf.ln(8)
    pdf.sub_title('No Partitioning for High-Volume Tables', 5)
    pdf.body_text(
        "Tables like vdetalle (sales detail) and ingresos (income) grow by hundreds "
        "of thousands of records daily. The views filter by current_date but scan "
        "the ENTIRE table to find today's records."
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Implement range partitioning by date (monthly or weekly) on vdetalle and ingresos. "
        "This allows PostgreSQL to scan only the current partition for today's queries."
    )
    pdf.code_block(
        "-- Partitioned table example\n"
        "CREATE TABLE vdetalle (\n"
        "  id BIGSERIAL, fecha1 DATE, ...\n"
        ") PARTITION BY RANGE (fecha1);\n\n"
        "CREATE TABLE vdetalle_2026_03\n"
        "  PARTITION OF vdetalle\n"
        "  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');"
    )

    # ==========================================
    # 3. Structural Issues
    # ==========================================
    pdf.add_page()
    pdf.section_title('3. Structural Issues', color=(200, 140, 20))

    # Issue 6
    pdf.check_page_break(50)
    pdf.severity_badge('warning', 'WARNING')
    pdf.ln(8)
    pdf.sub_title('Inconsistent Column Naming', 6)
    pdf.body_text("Current naming uses cryptic abbreviations that are hard to understand:")
    pdf.code_block(
        "cant1, cant3        -> What is cant2? Why not 'quantity_sold', 'quantity_received'?\n"
        "pre1~pre5           -> What are these 5 prices? No documentation\n"
        "bfallado, bmovido   -> Boolean prefixed with 'b' (Hungarian notation)\n"
        "fecha1, fecha       -> Multiple date columns with unclear purpose\n"
        "kk                  -> Alias for cntoffset in final view (meaningless name)\n"
        "nlocal              -> Same as sucursal? Confusing duplication"
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Adopt clear, descriptive column names: quantity_sold, quantity_received, "
        "price_retail, price_wholesale, is_defective, is_transferred, sale_date, etc."
    )

    # Issue 7
    pdf.check_page_break(50)
    pdf.severity_badge('warning', 'WARNING')
    pdf.ln(8)
    pdf.sub_title('Repetitive Soft Delete Pattern', 7)
    pdf.body_text(
        "Every JOIN and WHERE clause repeats 'borrado is false'. This is error-prone "
        "(forgetting it in one place corrupts results) and adds overhead."
    )
    pdf.code_block(
        "-- Current: repeated in every query\n"
        "WHERE c.borrado is false\n"
        "AND v1.borrado is false\n"
        "AND bfallado is false\n"
        "AND bmovido is false"
    )
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_text_color(0, 120, 60)
    pdf.cell(0, 6, 'Recommendation:', new_x="LMARGIN", new_y="NEXT")
    pdf.body_text(
        "Option A: Create base views that pre-filter deleted records.\n"
        "Option B: Use Row-Level Security (RLS) policies.\n"
        "Option C: Use partial indexes on (borrado = false)."
    )
    pdf.code_block(
        "-- Partial index: only indexes active records\n"
        "CREATE INDEX idx_vdetalle_active\n"
        "ON vdetalle (ref_id_codigo, fecha1)\n"
        "WHERE borrado = false AND bfallado = false AND bmovido = false;"
    )

    # Issue 8
    pdf.check_page_break(40)
    pdf.severity_badge('warning', 'WARNING')
    pdf.ln(8)
    pdf.sub_title('Hardcoded Sucursal Defaults', 8)
    pdf.body_text(
        "COALESCE(sucursal, 1) and COALESCE(nlocal, 1) hardcode branch 1 as default. "
        "This masks NULL data issues and can assign stock to the wrong branch silently."
    )

    # Issue 9
    pdf.check_page_break(40)
    pdf.severity_badge('warning', 'WARNING')
    pdf.ln(8)
    pdf.sub_title('Complex View Dependencies', 9)
    pdf.body_text(
        "The DROP/CREATE sequence must be executed in exact order. Any change to a base "
        "view requires dropping and recreating all dependent views. With 300 stores, "
        "schema changes become extremely risky (3,600+ views to update)."
    )

    # Issue 10
    pdf.check_page_break(40)
    pdf.severity_badge('info', 'INFO')
    pdf.ln(8)
    pdf.sub_title('Debug Queries in Production Script', 10)
    pdf.body_text(
        "Multiple commented-out SELECT statements throughout the script suggest "
        "ad-hoc debugging. These should be removed from production scripts and "
        "maintained separately in a development/testing environment."
    )

    # ==========================================
    # 4. Scalability Projection
    # ==========================================
    pdf.add_page()
    pdf.section_title('4. Scalability Impact Projection')

    pdf.body_text("Estimated data volume at scale:")

    # 테이블 형태로 표현
    pdf.set_font('Helvetica', 'B', 9)
    pdf.set_fill_color(30, 60, 120)
    pdf.set_text_color(255, 255, 255)
    headers = ['Metric', 'Current (1 store)', 'Scale (300 stores)', 'Growth/Year']
    widths = [45, 45, 50, 45]
    for i, h in enumerate(headers):
        pdf.cell(widths[i], 7, h, border=1, fill=True, align='C')
    pdf.ln()

    pdf.set_font('Helvetica', '', 9)
    pdf.set_text_color(40, 40, 40)
    rows = [
        ['Products', '20,000', '6,000,000', '+20%'],
        ['Variants', '100,000', '60,000,000', '+20%'],
        ['Daily Events', '1,000', '300,000', '+30%'],
        ['Annual Records', '365,000', '109,500,000', '+30%'],
        ['Views Created', '12', '3,600+', 'Linear'],
        ['Query Time (est.)', '< 1s', '10-30s+', 'Exponential'],
    ]
    for row in rows:
        for i, cell in enumerate(row):
            color = (255, 230, 230) if 'Exponential' in cell or '3,600' in cell else (255, 255, 255)
            pdf.set_fill_color(*color)
            pdf.cell(widths[i], 6, cell, border=1, fill=True, align='C')
        pdf.ln()

    pdf.ln(8)
    pdf.body_text(
        "The current architecture has O(n*m) complexity where n=products and m=events. "
        "At 300 stores, every stock query scans ~60M product records and joins with "
        "~100M+ event records. This is unsustainable without fundamental changes."
    )

    # ==========================================
    # 5. Recommended Architecture
    # ==========================================
    pdf.add_page()
    pdf.section_title('5. Recommended Architecture')

    pdf.sub_title('Option A: Denormalized Stock Table + Triggers (Recommended)')
    pdf.body_text(
        "Maintain a real-time stock_summary table updated atomically by triggers. "
        "This eliminates the need for view chains entirely."
    )
    pdf.code_block(
        "-- Stock summary table (replaces all views)\n"
        "CREATE TABLE stock_summary (\n"
        "  product_id    BIGINT REFERENCES products(id),\n"
        "  branch_id     INT REFERENCES branches(id),\n"
        "  total_income  INT DEFAULT 0,\n"
        "  total_sold    INT DEFAULT 0,\n"
        "  total_reserved INT DEFAULT 0,\n"
        "  total_offset  INT DEFAULT 0,\n"
        "  current_stock INT GENERATED ALWAYS AS\n"
        "    (total_income + total_offset - total_sold - total_reserved) STORED,\n"
        "  last_income_date DATE,\n"
        "  last_sale_date   DATE,\n"
        "  PRIMARY KEY (product_id, branch_id)\n"
        ");\n\n"
        "-- Trigger on sale insert\n"
        "CREATE FUNCTION update_stock_on_sale() RETURNS TRIGGER AS $$\n"
        "BEGIN\n"
        "  UPDATE stock_summary\n"
        "  SET total_sold = total_sold + NEW.quantity,\n"
        "      last_sale_date = NEW.sale_date\n"
        "  WHERE product_id = NEW.product_id\n"
        "    AND branch_id = NEW.branch_id;\n"
        "  RETURN NEW;\n"
        "END; $$ LANGUAGE plpgsql;"
    )
    pdf.body_text(
        "Benefits: O(1) stock lookup, no view chain, atomic updates, "
        "race condition safe with row-level locks."
    )

    pdf.check_page_break(50)
    pdf.sub_title('Option B: Materialized Views with Periodic Refresh')
    pdf.body_text(
        "If real-time accuracy is not required (e.g., stock checked every 5 minutes), "
        "convert views to MATERIALIZED VIEWs and refresh them periodically."
    )
    pdf.code_block(
        "CREATE MATERIALIZED VIEW stock_mv AS\n"
        "  SELECT ... (current view logic) ...;\n\n"
        "CREATE UNIQUE INDEX ON stock_mv (product_id, branch_id);\n\n"
        "-- Refresh every 5 minutes (no lock)\n"
        "REFRESH MATERIALIZED VIEW CONCURRENTLY stock_mv;"
    )
    pdf.body_text(
        "Less ideal than Option A but simpler to implement as a migration path."
    )

    # ==========================================
    # 6. Migration Priority
    # ==========================================
    pdf.check_page_break(80)
    pdf.section_title('6. Migration Priority')

    priorities = [
        ('1. IMMEDIATE', 'Add indexes on frequently filtered columns (borrado, ref_id_codigo, fecha)',
         'No schema change, 10-100x query speedup, zero downtime'),
        ('2. SHORT-TERM', 'Replace hardcoded _id_2 views with parameterized functions',
         'Eliminates 3,600+ view maintenance, enables multi-store'),
        ('3. MEDIUM-TERM', 'Implement stock_summary table with triggers',
         'O(1) stock lookup, eliminates view chain entirely'),
        ('4. MEDIUM-TERM', 'Add table partitioning on date-heavy tables',
         'Dramatic speedup for date-range queries'),
        ('5. LONG-TERM', 'Migrate to normalized schema with clear naming',
         'Improved maintainability and onboarding'),
    ]

    for priority, action, impact in priorities:
        pdf.check_page_break(25)
        pdf.set_font('Helvetica', 'B', 10)
        pdf.set_text_color(30, 60, 120)
        pdf.cell(0, 7, priority, new_x="LMARGIN", new_y="NEXT")
        pdf.set_font('Helvetica', '', 10)
        pdf.set_text_color(40, 40, 40)
        pdf.cell(0, 5.5, f"Action: {action}", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font('Helvetica', 'I', 9)
        pdf.set_text_color(80, 80, 80)
        pdf.cell(0, 5.5, f"Impact: {impact}", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(4)

    # ==========================================
    # 7. Conclusion
    # ==========================================
    pdf.check_page_break(40)
    pdf.section_title('7. Conclusion')
    pdf.body_text(
        "The current view-based architecture works at small scale (1-2 stores) but will "
        "face severe performance and maintenance challenges at 300 stores. The most "
        "impactful improvement is replacing the view chain with a denormalized "
        "stock_summary table maintained by database triggers. Combined with proper "
        "indexing and partitioning, this approach can handle the projected scale of "
        "6M+ products and 100M+ annual events while maintaining sub-second query times."
    )

    # 저장
    output_path = os.path.expanduser(
        '~/Trabajos_Programming/ACE_online_1.0/Legacy_SQL_Analysis_Report.pdf'
    )
    pdf.output(output_path)
    print(f"PDF generated: {output_path}")
    return output_path

if __name__ == '__main__':
    generate_report()
