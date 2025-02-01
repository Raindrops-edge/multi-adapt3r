import "./globals.css";
import type { Metadata } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

const jetbrains_mono = JetBrains_Mono({
  subsets: ["latin"],
  display: "swap",
  weight: ["100", "600"],
  variable: "--font-jetbrains-mono",
});

export const metadata: Metadata = {
  title: "Ghostty",
  description: "👻",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={`${inter.className} ${jetbrains_mono.variable}`}>
        {children}
      </body>
    </html>
  );
}
