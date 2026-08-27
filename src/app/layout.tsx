import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { ServiceWorkerRegistration } from "@/components/ServiceWorkerRegistration";
import "./globals.css";

export const metadata: Metadata = {
  title: "Performance Tracker",
  description:
    "A secure, organization-isolated performance tracking system",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Performance Tracker",
  },
  icons: {
    icon: "/icon.svg",
    apple: "/icon.svg",
  },
  applicationName: "Performance Tracker",
  keywords: [
    "Performance Tracker",
    "Organizational performance",
    "Performance management",
    "Secure appraisal",
  ],
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  themeColor: "#1e3a5f",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-slate-950 text-slate-100 antialiased min-h-screen selection:bg-cyan-500 selection:text-slate-950">
        <ServiceWorkerRegistration />
        {children}
      </body>
    </html>
  );
}
