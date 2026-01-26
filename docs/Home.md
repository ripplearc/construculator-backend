# Construculator Backend

Welcome to the Construculator backend documentation.

## Overview

Construculator is a construction cost estimation platform built on [Supabase](https://supabase.com). It helps construction professionals create, manage, and collaborate on project cost estimates.

## Key Features

- **Project Management** — Create and organize construction projects with team collaboration
- **Cost Estimation** — Build detailed estimates with materials, labor, and equipment costs
- **Calculations** — Support for area, volume, and slope calculations
- **Team Collaboration** — Comments, threads, task assignments, and real-time notifications
- **Role-Based Access** — Fine-grained permissions with Row-Level Security (RLS)

## Tech Stack

| Component | Technology |
|-----------|------------|
| Database | PostgreSQL (via Supabase) |
| Auth | Supabase Auth |
| Security | Row-Level Security policies |
| Storage | Supabase Storage + external providers (Google Drive, OneDrive, Dropbox) |

## Getting Started

```bash
# Install dependencies
npm install

# Start local Supabase
npx supabase start

# Run migrations
npx supabase db reset
```
