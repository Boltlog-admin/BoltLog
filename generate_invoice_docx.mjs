/**
 * Generates boltlog_receipt_2026-03-01.docx (mirrors generate_invoice.py).
 * Run: npm install && node generate_invoice_docx.mjs
 */
import fs from "fs";
import {
  Document,
  Packer,
  Paragraph,
  TextRun,
  Table,
  TableRow,
  TableCell,
} from "docx";

const todayStr = "2026-03-01";

function p(text, opts = {}) {
  return new Paragraph({
    children: [new TextRun({ text, ...opts })],
  });
}

function boldP(text) {
  return new Paragraph({
    children: [new TextRun({ text, bold: true })],
  });
}

function cell(text) {
  return new TableCell({
    children: [new Paragraph({ children: [new TextRun(text)] })],
  });
}

const headerRow = new TableRow({
  children: ["#", "Description", "Qty", "Rate", "Amount"].map((h) => cell(h)),
});

const row1 = new TableRow({
  children: [
    cell("1"),
    cell("Android application development (paid in full)"),
    cell("1"),
    cell("375"),
    cell("375"),
  ],
});

const row2 = new TableRow({
  children: [
    cell("2"),
    cell("Services integration"),
    cell("1"),
    cell("150"),
    cell("150"),
  ],
});

const doc = new Document({
  sections: [
    {
      children: [
        boldP("Fidinsky Tech Solutions"),
        p("Phone: +263779964877"),
        new Paragraph({ text: "" }),
        boldP("RECEIPT"),
        new Paragraph({
          children: [
            new TextRun({ text: `Date: ${todayStr}\n`, bold: true }),
            new TextRun({ text: "Status: PAID (Cash)", bold: true }),
          ],
        }),
        new Paragraph({ text: "" }),
        boldP("Client (Bill To)"),
        p("Client Name: BoltLog"),
        new Paragraph({ text: "" }),
        new Table({
          columnWidths: [900, 5200, 900, 900, 1100],
          rows: [headerRow, row1, row2],
        }),
        new Paragraph({ text: "" }),
        boldP("Total Paid: 525"),
        new Paragraph({ text: "" }),
        boldP("Payment Details"),
        new Paragraph({
          children: [
            new TextRun("Payment Method: Cash\n"),
            new TextRun("Amount Received: 525\n"),
            new TextRun(`Date Received: ${todayStr}`),
          ],
        }),
        new Paragraph({ text: "" }),
        boldP("Notes"),
        new Paragraph({
          children: [
            new TextRun(
              "Project / Reference: Android application development and services integration (totals $525).\n"
            ),
            new TextRun("Additional Notes: Thank you for your business."),
          ],
        }),
      ],
    },
  ],
});

const buffer = await Packer.toBuffer(doc);
const out = "boltlog_receipt_2026-03-01.docx";
fs.writeFileSync(out, buffer);
console.log(`Wrote ${out}`);
