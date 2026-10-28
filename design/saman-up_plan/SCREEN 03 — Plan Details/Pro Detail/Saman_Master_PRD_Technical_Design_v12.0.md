# Saman Master PRD & Technical Design Specification v12.0

**Project:** Saman Fitness  
**Document:** Project Brief — Executive Summary & Architecture Overview  
**Version:** 12.0

> Source: User-provided project brief. Milestone statuses below are reproduced as supplied; they do not independently confirm implementation or runtime verification.

The Product Requirements Document (PRD) & Technical Design Specification (v12.0) for Saman Fitness is fully compiled and active in your workspace as **Saman Master PRD & Technical Design Specification v12.0**.

## Executive Summary & Architecture Overview (v12.0)

### 1. Core Philosophy: Calm Athleticism

#### The 5-Second Athlete Contract

An athlete can answer three vital questions in under 5 seconds:

1. **What can I train today?** Immediate access to today's scheduled workout hero and movement splits without navigation friction.
2. **How do I start?** Frictionless one-tap initiation via **Start workout** or **Quick start**.
3. **Where can I see what I actually completed?** Chronological, mathematically verified volume history without vanity metrics or fabricated calories.

#### Aesthetic Principles

| Element | Specification |
| --- | --- |
| Deep Obsidian canvas | `#0C0D0E` |
| Charcoal surface cards | `#16171B` |
| Hairline graphite borders | `#26282F`, 1px |
| Headings | Space Grotesk |
| Interface typography | Inter |
| Tabular telemetry | JetBrains Mono |
| Performance Green | `#10B981` |
| Fuel Amber | `#F59E0B` |
| Metabolic Violet | `#A855F7` |

High-contrast typography and disciplined semantic accents define the visual system.

### 2. Tri-Mode Navigation Architecture

#### Persistent 5-Tab Navigation System

Global exploration across:

1. Home
2. Workout — Active Core
3. Saman Coach — S monogram
4. Nutrition
5. Profile

#### Dedicated In-Session Operational Mode

The bottom tab bar is suppressed during active lifting and **Live Form Check (Optical CV)** to prevent destructive context switching with sweaty or chalked hands.

#### Focused Sub-Flow / Sub-Page Mode

A safe-area top app bar provides explicit back routing. The global 5-tab bar is omitted to preserve task focus.

Examples include:

- Edit Profile
- Membership Overview
- Compare All Plans
- Plan Details

### 3. Mathematical Integrity & Audit Agreement

#### Lifting Volume Formula

$$
\text{Lifting Volume} = \text{External Load} \times \text{Completed Reps}
$$

Bodyweight movements contribute **zero kg load**.

#### Timed Sets

Timed sets count toward total sets and timed duration. They are excluded from rep totals and weight volume tallies.

#### Cross-Screen Audit Agreement

| Date | Session / Movement | Volume calculation | Timed work |
| --- | --- | --- | --- |
| Oct 10 | Dumbbell Bench Press | 24 kg × 8 = **192 kg** | — |
| Oct 8 | Upper Body Strength | 656 kg + 760 kg + 420 kg = **1,836 kg** | — |
| Oct 6 | Lower Body & Core | 480 kg + 570 kg = **1,050 kg** | **1m 30s** plank |

#### Monthly Training Total

$$
192 + 1{,}836 + 1{,}050 = \mathbf{3{,}078\text{ kg}}
$$

| Metric | Monthly total |
| --- | --- |
| Training volume | **3,078 kg** |
| Workouts | **3** |
| Sets | **14** |
| Duration | **1h 32m** |

#### Membership Annual Pricing Math

| Plan | Annual total (USD) | Calculation | Monthly equivalent (USD) |
| --- | ---: | --- | ---: |
| Plus | $60 / year | 60 ÷ 12 = 5 | **$5 / month** |
| Pro | $120 / year | 120 ÷ 12 = 10 | **$10 / month** |
| Ultra | $240 / year | 240 ÷ 12 = 20 | **$20 / month** |

### 4. Project Roadmap & Milestone Tracker

| Milestone | Deliverables & Scope | Status |
| --- | --- | --- |
| Milestones 1–4 | Calm Athleticism Tokens, Home Command Center, Workout Launchpad, Movement Library, Active Workout Stepper Matrix, Live Form Check (Optical CV), Workout History & Session Detail | Completed |
| Milestones 4.1–4.5 | Complete Onboarding Flow (Steps 1–5): Goal Selection, Demographics, Measurements, Activity Level, Review & Confirm with CP0 save state machine | Completed |
| Milestone 4.6 | Profile Tab (Tab 5) & Pre-CP0 Architecture: Friendly Summary, Edit CTA, Account Area, Loading & Fallback contracts | Completed |
| Milestone 5 | Prefilled "Edit Profile" Mutation Flow: Vertical flex container, 6-field continuous form, bottom sheets, discard dialog, and save state machine | Completed |
| Milestone 8 | Saman Membership Preview: Tier Architecture (Free, Plus, Pro, Ultra), Screen 01 (Overview), Screen 02 (Compare All Plans mobile matrix) | Completed |
| Milestone 8.1 | Plan Detail Sub-Screens: Shared template, Plus Plan Details (SCREEN 03A), Pro Plan Details (SCREEN 03B) in Monthly, Yearly, and Expanded views | Completed |
| Milestone 8.2 | Plan Detail Sub-Screens: Ultra Plan Details (SCREEN 03C — Peak Performance, Advanced Thinking & 5× Pro Allowance) | Completed |
| Milestone 6 | Post-Workout Review & Save Summary: RPE exertion logging, session recap, history commit | Next Up |
| Milestone 7 | Wearable Biometric Integration (Apple Health, Whoop) & JSON/CSV Training Diary Export | Scheduled |

## Recommended Next Steps

With the Membership Suite complete, we are ready to move into **Milestone 6: Post-Workout Review & Save Summary**.

### Design Milestone 6 Screen

A post-workout summary featuring:

- Duration tallies.
- Calculated total volume.
- RPE exertion logging — 1–10 slider or tactile dial.
- Muscle distribution breakdown.
- Final history commit button.

### Design Empty / Filtered States for Workout History

Complete edge-case designs for:

- Empty calendar weeks.
- Date filter resets.
