import React from "react";
import { ensureSeedData } from "@/lib/mduSeed";
import { MduApp } from "@/components/MduApp";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  // Ensure the MNDF MDU PostgreSQL database is seeded with realistic demo data on first load
  await ensureSeedData();

  return <MduApp />;
}
