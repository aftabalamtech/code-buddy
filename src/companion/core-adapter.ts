/**
 * Bridge to `@phuetz/companion-core` — the portable relational core extracted
 * from this repository so the robot and a future multi-persona app share ONE
 * implementation instead of two that drift.
 *
 * The core is opt-in with `CODEBUDDY_COMPANION_CORE=true`. When disabled,
 * every call delegates to the historical path. When enabled, the package is
 * loaded dynamically and failures fall back safely to the historical path.
 *
 * @module companion/core-adapter
 */

import { isCopinePersona, resolveCompanionPersona } from './personas/index.js';
import type { CompanionPersonaProfile } from './personas/types.js';
import {
  evolveTraits,
  type RelationalSignal,
  type RelationshipState,
} from './relationship-state.js';
import { applyLimitsContract, LIMITS_REPAIRS, type LimitsVerdict } from './reply-augment.js';
import { logger } from '../utils/logger.js';

// Keep this dependency genuinely optional at compile time. A variable module
// specifier prevents TypeScript from trying to resolve the optional workspace
// package during the main build. It is still resolved normally by Node at
// runtime when CODEBUDDY_COMPANION_CORE is enabled.
const COMPANION_CORE_PACKAGE = '@phuetz/companion-core';

type CoreModule = {
  safeLoadPersonaProfile(profile: unknown):
    | { ok: true; value: unknown }
    | { ok: false; issues: string[] };
  evolveRelationship(state: unknown, signal: unknown): unknown;
  applyLimitsContract(
    output: string,
    opts: { repairs: readonly string[]; heard?: string },
  ): { text: string; reason?: string };
};

let cached: CoreModule | null = null;
let loadFailed = false;

export function companionCoreEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  const raw = (env.CODEBUDDY_COMPANION_CORE ?? '').trim().toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'yes' || raw === 'on';
}

export async function loadCompanionCore(
  env: NodeJS.ProcessEnv = process.env,
): Promise<CoreModule | null> {
  if (!companionCoreEnabled(env)) return null;
  if (cached) return cached;
  if (loadFailed) return null;
  try {
    cached = (await import(COMPANION_CORE_PACKAGE)) as unknown as CoreModule;
    return cached;
  } catch (error) {
    loadFailed = true;
    logger.warn(
      `[companion-core] paquet indisponible, repli sur le chemin historique : ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return null;
  }
}

export function resetCompanionCoreCache(): void {
  cached = null;
  loadFailed = false;
}

export async function resolveCompanionPersonaViaCore(
  env: NodeJS.ProcessEnv = process.env,
): Promise<CompanionPersonaProfile | null> {
  const historical = resolveCompanionPersona(env);
  const core = await loadCompanionCore(env);
  if (!core || !historical) return historical;
  const validated = core.safeLoadPersonaProfile(historical);
  if (!validated.ok) {
    logger.warn(`[companion-core] profil « ${historical.id} » refusé : ${validated.issues.join(' ; ')}`);
    return historical;
  }
  return historical;
}

export async function validateCompanionPersona(
  profile: unknown,
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ ok: true } | { ok: false; issues: string[] }> {
  const core = await loadCompanionCore(env);
  if (!core) return { ok: true };
  const result = core.safeLoadPersonaProfile(profile);
  return result.ok ? { ok: true } : { ok: false, issues: result.issues };
}

export async function evolveTraitsViaCore(
  state: RelationshipState,
  signal: RelationalSignal,
  env: NodeJS.ProcessEnv = process.env,
): Promise<RelationshipState> {
  const core = await loadCompanionCore(env);
  if (!core) return evolveTraits(state, signal);
  return core.evolveRelationship(state, signal) as RelationshipState;
}

export async function applyLimitsContractViaCore(
  output: string,
  opts: { heard?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<LimitsVerdict> {
  const env = opts.env ?? process.env;
  const core = await loadCompanionCore(env);
  if (!core) return applyLimitsContract(output, opts);
  if (!isCopinePersona(env)) return { text: output };
  const verdict = core.applyLimitsContract(output, {
    repairs: LIMITS_REPAIRS,
    ...(opts.heard ? { heard: opts.heard } : {}),
  });
  return verdict.reason ? { text: verdict.text, reason: verdict.reason } : { text: verdict.text };
}
