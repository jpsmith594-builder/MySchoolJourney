-- Reference data for My High School Journal (draft).
-- Subject list follows South African CAPS naming. Extend as real reports show what is missing.

insert into subjects (key, name, short_name, category, min_grade, max_grade) values
  ('english_hl',            'English Home Language',                 'English HL',   'language',    1, 12),
  ('afrikaans_fal',         'Afrikaans First Additional Language',   'Afrikaans FAL','language',    1, 12),
  ('isizulu_hl',            'isiZulu Home Language',                 'isiZulu HL',   'language',    1, 12),
  ('mathematics',           'Mathematics',                           'Maths',        'mathematics', 1, 12),
  ('mathematical_literacy', 'Mathematical Literacy',                 'Maths Lit',    'mathematics', 10, 12),
  ('natural_sciences',      'Natural Sciences',                      'Nat Sci',      'science',     4, 9),
  ('physical_sciences',     'Physical Sciences',                     'Phys Sci',     'science',     10, 12),
  ('life_sciences',         'Life Sciences',                         'Life Sci',     'science',     10, 12),
  ('geography',             'Geography',                             'Geography',    'humanities',  7, 12),
  ('history',               'History',                               'History',      'humanities',  7, 12),
  ('social_sciences',       'Social Sciences',                       'Soc Sci',      'humanities',  4, 9),
  ('life_orientation',      'Life Orientation',                      'LO',           'life_skills', 1, 12),
  ('accounting',            'Accounting',                            'Accounting',   'commerce',    10, 12),
  ('business_studies',      'Business Studies',                      'Business',     'commerce',    10, 12),
  ('economics',             'Economics',                             'Economics',    'commerce',    10, 12),
  ('ems',                   'Economic and Management Sciences',      'EMS',          'commerce',    7, 9),
  ('technology',            'Technology',                            'Technology',   'technology',  4, 9),
  ('creative_arts',         'Creative Arts',                         'Creative Arts','arts',        4, 9),
  ('visual_arts',           'Visual Arts',                           'Visual Arts',  'arts',        10, 12);

-- Names seen on real reports. Always lower case.
insert into subject_aliases (alias, subject_id)
select a.alias, s.id
from (values
  ('english hl', 'english_hl'), ('english home language', 'english_hl'), ('english', 'english_hl'),
  ('afrikaans fal', 'afrikaans_fal'), ('afrikaans eat', 'afrikaans_fal'),
  ('afrikaans eerste addisionele taal', 'afrikaans_fal'), ('afrikaans', 'afrikaans_fal'),
  ('isizulu hl', 'isizulu_hl'), ('isizulu', 'isizulu_hl'),
  ('maths', 'mathematics'), ('math', 'mathematics'), ('mathematics', 'mathematics'), ('wiskunde', 'mathematics'),
  ('maths lit', 'mathematical_literacy'), ('math lit', 'mathematical_literacy'),
  ('mathematical literacy', 'mathematical_literacy'), ('wiskundige geletterdheid', 'mathematical_literacy'),
  ('natural sciences', 'natural_sciences'), ('nat sci', 'natural_sciences'), ('natural science', 'natural_sciences'),
  ('physical sciences', 'physical_sciences'), ('physical science', 'physical_sciences'),
  ('phys sci', 'physical_sciences'), ('fisiese wetenskappe', 'physical_sciences'),
  ('life sciences', 'life_sciences'), ('life science', 'life_sciences'), ('life sci', 'life_sciences'),
  ('lewenswetenskappe', 'life_sciences'),
  ('geography', 'geography'), ('geo', 'geography'), ('geografie', 'geography'),
  ('history', 'history'), ('geskiedenis', 'history'),
  ('social sciences', 'social_sciences'), ('soc sci', 'social_sciences'),
  ('life orientation', 'life_orientation'), ('lo', 'life_orientation'), ('lewensoriëntering', 'life_orientation'),
  ('accounting', 'accounting'), ('rekeningkunde', 'accounting'),
  ('business studies', 'business_studies'), ('besigheidstudie', 'business_studies'),
  ('economics', 'economics'), ('ekonomie', 'economics'),
  ('ems', 'ems'), ('economic and management sciences', 'ems'),
  ('technology', 'technology'), ('tegnologie', 'technology'),
  ('creative arts', 'creative_arts'), ('visual arts', 'visual_arts')
) as a(alias, subject_key)
join subjects s on s.key = a.subject_key;

insert into career_fields (key, name, summary, requirements_note) values
  ('environmental_earth_sciences', 'Environmental and earth sciences',
   'Work in conservation, water, mining rehabilitation or climate research.',
   'Usually builds on Geography, Life Sciences and Maths. Check each institution for current requirements.'),
  ('languages_law_media', 'Languages, law and media',
   'Law, journalism, teaching or communications.',
   'Usually asks for strong language marks. Check each institution for current requirements.'),
  ('health_sciences', 'Health sciences',
   'Nursing, physiotherapy, pharmacy or medicine.',
   'Usually asks for strong Maths, Life Sciences and Physical Sciences, and entry scores differ by university.'),
  ('engineering_technology', 'Engineering and technology',
   'Civil, electrical, mechanical and software engineering, and related fields.',
   'Usually asks for strong Maths and Physical Sciences. Check each institution for current requirements.'),
  ('commerce_finance', 'Commerce and finance',
   'Accounting, auditing, economics, business and financial services.',
   'Requirements vary by programme, and some ask for Mathematics rather than Mathematical Literacy.');

insert into career_field_subjects (career_field_id, subject_id, weight)
select c.id, s.id, m.weight
from (values
  ('environmental_earth_sciences', 'geography',             'core'),
  ('environmental_earth_sciences', 'life_sciences',         'core'),
  ('environmental_earth_sciences', 'mathematics',           'helpful'),
  ('environmental_earth_sciences', 'physical_sciences',     'helpful'),
  ('languages_law_media',          'english_hl',            'core'),
  ('languages_law_media',          'afrikaans_fal',         'helpful'),
  ('languages_law_media',          'history',               'helpful'),
  ('health_sciences',              'life_sciences',         'core'),
  ('health_sciences',              'mathematics',           'core'),
  ('health_sciences',              'physical_sciences',     'core'),
  ('engineering_technology',       'mathematics',           'core'),
  ('engineering_technology',       'physical_sciences',     'core'),
  ('commerce_finance',             'accounting',            'core'),
  ('commerce_finance',             'economics',             'core'),
  ('commerce_finance',             'mathematics',           'helpful'),
  ('commerce_finance',             'business_studies',      'helpful')
) as m(field_key, subject_key, weight)
join career_fields c on c.key = m.field_key
join subjects s      on s.key = m.subject_key;
