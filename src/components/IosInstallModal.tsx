"use client";

import React from "react";
import { X, Share, PlusSquare, Smartphone, ShieldCheck } from "lucide-react";

interface IosInstallModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function IosInstallModal({ isOpen, onClose }: IosInstallModalProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm animate-in fade-in duration-200">
      <div className="relative w-full max-w-md rounded-2xl bg-slate-900 border border-slate-700 p-6 shadow-2xl text-slate-100">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 rounded-full p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          aria-label="Close"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="flex items-center gap-3 border-b border-slate-800 pb-4 mb-5">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-cyan-950 border border-cyan-700 text-cyan-400">
            <Smartphone className="w-6 h-6" />
          </div>
          <div>
            <h3 className="text-lg font-bold text-white tracking-wide">
              Install on iPhone / iOS
            </h3>
            <p className="text-xs text-slate-400">
              Download as a standalone Progressive Web App (PWA)
            </p>
          </div>
        </div>

        <div className="space-y-4 text-sm">
          <div className="flex items-start gap-3.5 bg-slate-800/60 rounded-xl p-3.5 border border-slate-700/60">
            <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-cyan-500/20 text-cyan-400 font-bold text-xs">
              1
            </div>
            <div>
              <p className="font-semibold text-slate-200">
                Tap the Share icon in Safari
              </p>
              <p className="text-xs text-slate-400 mt-0.5">
                Look for the <span className="inline-flex items-center text-cyan-400 font-medium"><Share className="w-3.5 h-3.5 mx-1 inline" /> Share</span> button in the Safari bottom toolbar on your iPhone.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3.5 bg-slate-800/60 rounded-xl p-3.5 border border-slate-700/60">
            <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-cyan-500/20 text-cyan-400 font-bold text-xs">
              2
            </div>
            <div>
              <p className="font-semibold text-slate-200">
                Select &ldquo;Add to Home Screen&rdquo;
              </p>
              <p className="text-xs text-slate-400 mt-0.5">
                Scroll down the share menu and tap <span className="inline-flex items-center text-cyan-400 font-medium"><PlusSquare className="w-3.5 h-3.5 mx-1 inline" /> Add to Home Screen</span>.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3.5 bg-slate-800/60 rounded-xl p-3.5 border border-slate-700/60">
            <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-cyan-500/20 text-cyan-400 font-bold text-xs">
              3
            </div>
            <div>
              <p className="font-semibold text-slate-200">
                Tap &ldquo;Add&rdquo; in the top-right corner
              </p>
              <p className="text-xs text-slate-400 mt-0.5">
                Confirm the app title <strong>MNDF PDS</strong>. It will appear on your iPhone home screen with the MNDF Marine emblem, ready for full-screen field evaluations.
              </p>
            </div>
          </div>
        </div>

        <div className="mt-6 flex items-center justify-between border-t border-slate-800 pt-4">
          <div className="flex items-center gap-2 text-xs text-emerald-400">
            <ShieldCheck className="w-4 h-4 shrink-0" />
            <span>Secure offline-capable PWA</span>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg bg-cyan-600 px-5 py-2 text-sm font-semibold text-white shadow-lg hover:bg-cyan-500 transition-colors"
          >
            Got It
          </button>
        </div>
      </div>
    </div>
  );
}
