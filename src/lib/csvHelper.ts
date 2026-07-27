import { MarinePersonnel } from "@/types/mdu";
import { MNDF_RANKS } from "@/lib/mduConstants";

export interface ParsedMarineCsv {
  serviceNo: string;
  rank: string;
  name: string;
  platoon: string;
  role: string;
}

export function parsePersonnelCsv(text: string): {
  valid: ParsedMarineCsv[];
  errors: string[];
} {
  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  if (lines.length === 0) {
    return { valid: [], errors: ["The uploaded file is empty."] };
  }

  // Check if first line is a header
  const firstLine = lines[0].toLowerCase();
  const hasHeader =
    firstLine.includes("service") ||
    firstLine.includes("rank") ||
    firstLine.includes("name") ||
    firstLine.includes("platoon") ||
    firstLine.includes("role");

  const dataLines = hasHeader ? lines.slice(1) : lines;
  const valid: ParsedMarineCsv[] = [];
  const errors: string[] = [];

  const validRanks = new Set(MNDF_RANKS.map((r) => r.code.toLowerCase()));

  for (let i = 0; i < dataLines.length; i++) {
    const line = dataLines[i];
    // Simple CSV parser handling quotes
    const cols: string[] = [];
    let current = "";
    let inQuotes = false;
    for (let c = 0; c < line.length; c++) {
      const char = line[c];
      if (char === '"' && line[c + 1] === '"') {
        current += '"';
        c++;
      } else if (char === '"') {
        inQuotes = !inQuotes;
      } else if (char === "," && !inQuotes) {
        cols.push(current.trim());
        current = "";
      } else {
        current += char;
      }
    }
    cols.push(current.trim());

    if (cols.length < 3) {
      errors.push(`Row ${i + 1}: Line needs at least Service Number, Rank, and Name.`);
      continue;
    }

    const serviceNo = cols[0];
    let rankCode = cols[1];
    const name = cols[2];
    const platoon = cols[3] || "Alpha Platoon - MDU";
    const role = cols[4] || "Marine Rifleman";

    // Normalize rank casing (e.g. "sgt" -> "Sgt", "pte" -> "Pte", "maj" -> "Maj")
    const matchRank = MNDF_RANKS.find(
      (r) =>
        r.code.toLowerCase() === rankCode.toLowerCase() ||
        r.label.toLowerCase().includes(rankCode.toLowerCase())
    );

    if (matchRank) {
      rankCode = matchRank.code;
    } else {
      errors.push(`Row ${i + 1} (${serviceNo}): Unrecognized MNDF rank "${rankCode}". Defaulting to Pte.`);
      rankCode = "Pte";
    }

    if (!serviceNo || !name) {
      errors.push(`Row ${i + 1}: Service Number and Name are required.`);
      continue;
    }

    valid.push({
      serviceNo,
      rank: rankCode,
      name,
      platoon,
      role,
    });
  }

  return { valid, errors };
}

export function downloadSampleCsvTemplate() {
  const headers = "serviceNo,rank,name,platoon,role";
  const rows = [
    "MNDF-1001,Maj,R. Shiham,MDU Command HQ,Marine Deployment Unit Commander",
    "MNDF-1002,Cpt,M. Fazeel,Alpha Platoon - MDU,Platoon Commander",
    "MNDF-1003,FLt,A. Zameer,Bravo Platoon - MDU,Platoon Commander",
    "MNDF-1004,1SG,M. Nabeel,MDU Command HQ,Company First Sergeant",
    "MNDF-1005,SFC,H. Rasheed,Alpha Platoon - MDU,Platoon Sergeant",
    "MNDF-1006,SSgt,T. Moosa,Bravo Platoon - MDU,Platoon Sergeant",
    "MNDF-1007,Sgt,M. Misbaah,Alpha Platoon - MDU,Section Commander",
    "MNDF-1008,Cpl,A. Naseer,Alpha Platoon - MDU,Team Leader",
    "MNDF-1009,LCpl,H. Ibrahim,Alpha Platoon - MDU,Assault Rifleman",
    "MNDF-1010,Pte,S. Shaheem,Bravo Platoon - MDU,Marine Rifleman",
  ];
  const csvContent = [headers, ...rows].join("\n");
  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.setAttribute("download", "MNDF_MDU_Personnel_Template.csv");
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
