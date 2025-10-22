-- Cost estimates seeder
-- This file creates sample cost estimates with various markup configurations

INSERT INTO "cost_estimates" (
  "id",
  "project_id",
  "estimate_name",
  "estimate_description",
  "creator_user_id",
  "markup_type",
  "overall_markup_value_type",
  "overall_markup_value",
  "material_markup_value_type",
  "material_markup_value",
  "labor_markup_value_type",
  "labor_markup_value",
  "equipment_markup_value_type",
  "equipment_markup_value",
  "total_cost",
  "is_locked"
) VALUES
  -- Downtown Office Complex - Overall markup estimate
  (
    'a50e8400-e29b-41d4-a716-446655440001',
    '950e8400-e29b-41d4-a716-446655440001',
    'Initial Construction Estimate',
    'Preliminary cost estimate for the downtown office complex construction including all major components',
    '750e8400-e29b-41d4-a716-446655440000',
    'overall',
    'percentage',
    15.00,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    2500000.00,
    false
  ),
  
  -- Downtown Office Complex - Granular markup estimate
  (
    'a50e8400-e29b-41d4-a716-446655440002',
    '950e8400-e29b-41d4-a716-446655440001',
    'Detailed Cost Breakdown',
    'Detailed estimate with separate markup rates for materials, labor, and equipment',
    '750e8400-e29b-41d4-a716-446655440000',
    'granular',
    NULL,
    NULL,
    'percentage',
    12.00,
    'percentage',
    18.00,
    'percentage',
    10.00,
    2750000.00,
    true
  ),
  
  -- Residential Housing Development - Simple estimate
  (
    'a50e8400-e29b-41d4-a716-446655440003',
    '950e8400-e29b-41d4-a716-446655440002',
    'Phase 1 Housing Units',
    'Cost estimate for the first 25 housing units in the residential development',
    '750e8400-e29b-41d4-a716-446655440000',
    'overall',
    'amount',
    50000.00,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    1200000.00,
    false
  ),
  
  -- Shopping Mall Renovation - Complex estimate
  (
    'a50e8400-e29b-41d4-a716-446655440004',
    '950e8400-e29b-41d4-a716-446655440003',
    'Complete Renovation Estimate',
    'Comprehensive cost estimate for shopping mall renovation including structural changes and new installations',
    '750e8400-e29b-41d4-a716-446655440000',
    'granular',
    NULL,
    NULL,
    'percentage',
    8.00,
    'percentage',
    22.00,
    'amount',
    15000.00,
    1800000.00,
    false
  ),
  
  -- Industrial Warehouse - Basic estimate
  (
    'a50e8400-e29b-41d4-a716-446655440005',
    '950e8400-e29b-41d4-a716-446655440004',
    'Warehouse Construction Estimate',
    'Cost estimate for industrial warehouse construction including foundation, structure, and utilities',
    '750e8400-e29b-41d4-a716-446655440000',
    'overall',
    'percentage',
    20.00,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    3200000.00,
    true
  ),
  
  -- Downtown Office Complex - Revised estimate
  (
    'a50e8400-e29b-41d4-a716-446655440006',
    '950e8400-e29b-41d4-a716-446655440001',
    'Revised Estimate v2.0',
    'Updated cost estimate after design changes and material price adjustments',
    '750e8400-e29b-41d4-a716-446655440000',
    'granular',
    NULL,
    NULL,
    'percentage',
    14.00,
    'percentage',
    16.00,
    'percentage',
    12.00,
    2900000.00,
    false
  )
ON CONFLICT ("id") DO NOTHING;
