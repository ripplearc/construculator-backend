begin;
select plan(8);

-- PROJECTS table relationships
SELECT col_is_fk('public', 'projects', 'creator_user_id', 'projects.creator_user_id is a FK to users');
SELECT col_is_fk('public', 'projects', 'owning_company_id', 'projects.owning_company_id is a FK to companies');

-- COST_ESTIMATES table relationships
SELECT col_is_fk('public', 'cost_estimates', 'project_id', 'cost_estimates.project_id is a FK to projects');
SELECT col_is_fk('public', 'cost_estimates', 'creator_user_id', 'cost_estimates.creator_user_id is a FK to users');

-- THREADS table relationships
SELECT col_is_fk('public', 'threads', 'cost_item_id', 'threads.cost_item_id is a FK to cost_items');
SELECT col_is_fk('public', 'threads', 'creator_user_id', 'threads.creator_user_id is a FK to users');

-- COMMENTS table relationships
SELECT col_is_fk('public', 'comments', 'thread_id', 'comments.thread_id is a FK to threads');
SELECT col_is_fk('public', 'comments', 'author_user_id', 'comments.author_user_id is a FK to users');

select * from finish();
rollback;