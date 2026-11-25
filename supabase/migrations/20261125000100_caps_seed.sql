-- Reference data for My School Journey: the CAPS curriculum (Grades R to 12), plus career fields.
--
-- Sources: DBE National Policy Pertaining to the Programme and Promotion Requirements of the NCS Grades R-12
-- (phase structure, languages, non-official languages), the DBE Grade 10-12 CAPS/ATP subject list
-- (including the Technology and Music specialisations), and the NSC subject groupings published by the IEB
-- (non-official languages and the other approved subjects at Grades 10-12).
--
-- Not included on purpose, because they are not yet in the final CAPS or have no published grade or level:
-- Coding and Robotics (draft, being piloted), Kiswahili (optional, phased rollout), Khoi, Nama and San
-- (newly announced), occupational subjects, and Sign Language at First and Second Additional level.
-- Families can add any of these as an extra subject for their learner.
--
-- min_grade / max_grade are typical ranges used to suggest subjects. They are not enforced.
-- Keys that already existed in v0.1 (english_hl, afrikaans_fal, isizulu_hl, mathematics, ...) are unchanged.

-- ---------------------------------------------------------------------
-- Languages
-- ---------------------------------------------------------------------

-- The 11 official languages at Home (Gr R-12), First Additional (Gr 1-12) and Second Additional (Gr 4-12) level.
insert into subjects (key, name, short_name, category, min_grade, max_grade)
select l.k || '_' || lv.code,
       l.name || ' ' || lv.name,
       l.name || ' ' || upper(lv.code),
       'language', lv.min_g, 12
from (values
  ('afrikaans',  'Afrikaans'),
  ('english',    'English'),
  ('isindebele', 'isiNdebele'),
  ('isixhosa',   'isiXhosa'),
  ('isizulu',    'isiZulu'),
  ('sepedi',     'Sepedi'),
  ('sesotho',    'Sesotho'),
  ('setswana',   'Setswana'),
  ('siswati',    'siSwati'),
  ('tshivenda',  'Tshivenda'),
  ('xitsonga',   'Xitsonga')
) as l(k, name)
cross join (values
  ('hl',  'Home Language',              0),
  ('fal', 'First Additional Language',  1),
  ('sal', 'Second Additional Language', 4)
) as lv(code, name, min_g);

-- South African Sign Language, Home Language (Gr R-12).
insert into subjects (key, name, short_name, category, min_grade, max_grade)
values ('sasl_hl', 'South African Sign Language Home Language', 'SASL HL', 'language', 0, 12);

-- Non-official languages. German, Mandarin and Serbian appear from Grade 4; the rest are Grade 10-12 NSC options.
insert into subjects (key, name, short_name, category, min_grade, max_grade)
select n.k || '_' || lower(n.code),
       n.name || ' ' || lv.name,
       n.name || ' ' || n.code,
       'language', n.min_g, 12
from (values
  ('german',       'German',       'HL',  10),
  ('german',       'German',       'SAL',  4),
  ('mandarin',     'Mandarin',     'SAL',  4),
  ('serbian',      'Serbian',      'HL',   4),
  ('serbian',      'Serbian',      'SAL',  4),
  ('arabic',       'Arabic',       'SAL', 10),
  ('french',       'French',       'SAL', 10),
  ('gujarati',     'Gujarati',     'HL',  10),
  ('gujarati',     'Gujarati',     'FAL', 10),
  ('gujarati',     'Gujarati',     'SAL', 10),
  ('hebrew',       'Hebrew',       'SAL', 10),
  ('hindi',        'Hindi',        'HL',  10),
  ('hindi',        'Hindi',        'FAL', 10),
  ('hindi',        'Hindi',        'SAL', 10),
  ('italian',      'Italian',      'SAL', 10),
  ('latin',        'Latin',        'SAL', 10),
  ('modern_greek', 'Modern Greek', 'SAL', 10),
  ('portuguese',   'Portuguese',   'HL',  10),
  ('portuguese',   'Portuguese',   'SAL', 10),
  ('spanish',      'Spanish',      'SAL', 10),
  ('tamil',        'Tamil',        'HL',  10),
  ('tamil',        'Tamil',        'FAL', 10),
  ('tamil',        'Tamil',        'SAL', 10),
  ('telugu',       'Telugu',       'HL',  10),
  ('telugu',       'Telugu',       'FAL', 10),
  ('telugu',       'Telugu',       'SAL', 10),
  ('urdu',         'Urdu',         'HL',  10),
  ('urdu',         'Urdu',         'FAL', 10),
  ('urdu',         'Urdu',         'SAL', 10)
) as n(k, name, code, min_g)
join (values
  ('HL',  'Home Language'),
  ('FAL', 'First Additional Language'),
  ('SAL', 'Second Additional Language')
) as lv(code, name) on lv.code = n.code;

-- ---------------------------------------------------------------------
-- All other subjects, Grade R to 12
-- ---------------------------------------------------------------------
insert into subjects (key, name, short_name, category, min_grade, max_grade) values
  -- Mathematics: all phases, then the Grade 10-12 options
  ('mathematics',                          'Mathematics',                       'Maths',          'mathematics', 0, 12),
  ('mathematical_literacy',                'Mathematical Literacy',             'Maths Lit',      'mathematics', 10, 12),
  ('technical_mathematics',                'Technical Mathematics',             'Tech Maths',     'mathematics', 10, 12),

  -- Foundation and Intermediate Phase: Life Skills and its components
  ('life_skills',                          'Life Skills',                       'Life Skills',    'life_skills', 0, 6),
  ('life_skills_beginning_knowledge',      'Beginning Knowledge',               'Beg. Knowledge', 'life_skills', 0, 3),
  ('life_skills_creative_arts',            'Creative Arts (Life Skills)',       'Creative Arts',  'arts',        0, 6),
  ('life_skills_physical_education',       'Physical Education',                'PE',             'life_skills', 0, 6),
  ('life_skills_personal_social_wellbeing','Personal and Social Wellbeing',     'PSW',            'life_skills', 0, 6),

  -- Intermediate and Senior Phase
  ('natural_sciences_technology',          'Natural Sciences and Technology',   'NST',            'science',     4, 6),
  ('social_sciences',                      'Social Sciences',                   'Soc Sci',        'humanities',  4, 9),
  ('natural_sciences',                     'Natural Sciences',                  'Nat Sci',        'science',     7, 9),
  ('technology',                           'Technology',                        'Technology',     'technology',  7, 9),
  ('ems',                                  'Economic and Management Sciences',  'EMS',            'commerce',    7, 9),
  ('creative_arts',                        'Creative Arts',                     'Creative Arts',  'arts',        7, 9),
  ('creative_arts_dance',                  'Creative Arts: Dance',              'CA Dance',       'arts',        7, 9),
  ('creative_arts_drama',                  'Creative Arts: Drama',              'CA Drama',       'arts',        7, 9),
  ('creative_arts_music',                  'Creative Arts: Music',              'CA Music',       'arts',        7, 9),
  ('creative_arts_visual_arts',            'Creative Arts: Visual Arts',        'CA Visual Arts', 'arts',        7, 9),
  ('life_orientation',                     'Life Orientation',                  'LO',             'life_skills', 7, 12),

  -- History and Geography: components of Social Sciences in Grades 4-9, subjects of their own in Grades 10-12
  ('history',                              'History',                           'History',        'humanities',  4, 12),
  ('geography',                            'Geography',                         'Geography',      'humanities',  4, 12),

  -- FET sciences
  ('physical_sciences',                    'Physical Sciences',                 'Phys Sci',       'science',     10, 12),
  ('technical_sciences',                   'Technical Sciences',                'Tech Sci',       'science',     10, 12),
  ('life_sciences',                        'Life Sciences',                     'Life Sci',       'science',     10, 12),

  -- FET commerce and services
  ('accounting',                           'Accounting',                        'Accounting',     'commerce',    10, 12),
  ('business_studies',                     'Business Studies',                  'Business',       'commerce',    10, 12),
  ('economics',                            'Economics',                         'Economics',      'commerce',    10, 12),
  ('consumer_studies',                     'Consumer Studies',                  'Consumer',       'services',    10, 12),
  ('hospitality_studies',                  'Hospitality Studies',               'Hospitality',    'services',    10, 12),
  ('tourism',                              'Tourism',                           'Tourism',        'services',    10, 12),

  -- FET agriculture
  ('agricultural_sciences',                'Agricultural Sciences',             'Agri Sci',       'agriculture', 10, 12),
  ('agricultural_management_practices',    'Agricultural Management Practices', 'AMP',            'agriculture', 10, 12),
  ('agricultural_technology',              'Agricultural Technology',           'Agri Tech',      'agriculture', 10, 12),

  -- FET technology
  ('computer_applications_technology',     'Computer Applications Technology',  'CAT',            'technology',  10, 12),
  ('information_technology',               'Information Technology',            'IT',             'technology',  10, 12),
  ('engineering_graphics_and_design',      'Engineering Graphics and Design',   'EGD',            'technology',  10, 12),
  ('civil_technology_civil_services',      'Civil Technology: Civil Services',  'Civil Services', 'technology',  10, 12),
  ('civil_technology_construction',        'Civil Technology: Construction',    'Construction',   'technology',  10, 12),
  ('civil_technology_woodworking',         'Civil Technology: Woodworking',     'Woodworking',    'technology',  10, 12),
  ('electrical_technology_digital_electronics', 'Electrical Technology: Digital Electronics', 'Digital Electronics', 'technology', 10, 12),
  ('electrical_technology_electronics',    'Electrical Technology: Electronics','Electronics',    'technology',  10, 12),
  ('electrical_technology_power_systems',  'Electrical Technology: Power Systems','Power Systems','technology',  10, 12),
  ('mechanical_technology_automotive',     'Mechanical Technology: Automotive', 'Automotive',     'technology',  10, 12),
  ('mechanical_technology_fitting_and_machining', 'Mechanical Technology: Fitting and Machining', 'Fitting and Machining', 'technology', 10, 12),
  ('mechanical_technology_welding_and_metalwork', 'Mechanical Technology: Welding and Metalwork', 'Welding and Metalwork', 'technology', 10, 12),

  -- FET arts
  ('dance_studies',                        'Dance Studies',                     'Dance',          'arts',        10, 12),
  ('design',                               'Design',                            'Design',         'arts',        10, 12),
  ('dramatic_arts',                        'Dramatic Arts',                     'Dramatic Arts',  'arts',        10, 12),
  ('visual_arts',                          'Visual Arts',                       'Visual Arts',    'arts',        10, 12),
  ('music_iam',                            'Music: Indigenous African Music',   'Music IAM',      'arts',        10, 12),
  ('music_jazz',                           'Music: Jazz',                       'Music Jazz',     'arts',        10, 12),
  ('music_wam',                            'Music: Western Art Music',          'Music WAM',      'arts',        10, 12),

  -- FET humanities
  ('religion_studies',                     'Religion Studies',                  'Religion',       'humanities',  10, 12),

  -- Other approved NSC subjects at Grades 10-12
  ('equine_studies',                       'Equine Studies',                    'Equine',         'other',       10, 12),
  ('marine_sciences',                      'Marine Sciences',                   'Marine Sci',     'science',     10, 12),
  ('maritime_economics',                   'Maritime Economics',                'Maritime Econ',  'commerce',    10, 12),
  ('nautical_science',                     'Nautical Science',                  'Nautical Sci',   'other',       10, 12),
  ('sport_and_exercise_science',           'Sport and Exercise Science',        'Sport Sci',      'science',     10, 12);

update subjects set is_life_orientation = true where key = 'life_orientation';

-- Components and their umbrella subjects (see the comment on subjects.parent_subject_id).
update subjects c
   set parent_subject_id = p.id
  from (values
    ('history',                               'social_sciences'),
    ('geography',                             'social_sciences'),
    ('life_skills_beginning_knowledge',       'life_skills'),
    ('life_skills_creative_arts',             'life_skills'),
    ('life_skills_physical_education',        'life_skills'),
    ('life_skills_personal_social_wellbeing', 'life_skills'),
    ('creative_arts_dance',                   'creative_arts'),
    ('creative_arts_drama',                   'creative_arts'),
    ('creative_arts_music',                   'creative_arts'),
    ('creative_arts_visual_arts',             'creative_arts')
  ) as m(child_key, parent_key)
  join subjects p on p.key = m.parent_key
 where c.key = m.child_key;

-- ---------------------------------------------------------------------
-- Aliases: abbreviations and Afrikaans names people type or see on reports. Lower case.
-- A missing subject key fails loudly (the subselect returns null).
-- ---------------------------------------------------------------------
insert into subject_aliases (alias, subject_id)
select a.alias, (select id from subjects where key = a.k)
from (values
  ('afrikaans huistaal',                 'afrikaans_hl'),
  ('afrikaans eerste addisionele taal',  'afrikaans_fal'),
  ('afrikaans eat',                      'afrikaans_fal'),
  ('afrikaans tweede addisionele taal',  'afrikaans_sal'),
  ('afrikaans tat',                      'afrikaans_sal'),
  ('maths',                              'mathematics'),
  ('math',                               'mathematics'),
  ('wiskunde',                           'mathematics'),
  ('maths lit',                          'mathematical_literacy'),
  ('math lit',                           'mathematical_literacy'),
  ('wiskundige geletterdheid',           'mathematical_literacy'),
  ('tech maths',                         'technical_mathematics'),
  ('technical maths',                    'technical_mathematics'),
  ('tegniese wiskunde',                  'technical_mathematics'),
  ('lewensvaardighede',                  'life_skills'),
  ('pe',                                 'life_skills_physical_education'),
  ('nst',                                'natural_sciences_technology'),
  ('natuurwetenskappe en tegnologie',    'natural_sciences_technology'),
  ('nat sci',                            'natural_sciences'),
  ('natural science',                    'natural_sciences'),
  ('natuurwetenskappe',                  'natural_sciences'),
  ('tegnologie',                         'technology'),
  ('ems',                                'ems'),
  ('ebw',                                'ems'),
  ('ekonomiese en bestuurswetenskappe',  'ems'),
  ('soc sci',                            'social_sciences'),
  ('social science',                     'social_sciences'),
  ('maatskaplike wetenskappe',           'social_sciences'),
  ('arts and culture',                   'creative_arts'),
  ('skeppende kunste',                   'creative_arts'),
  ('lo',                                 'life_orientation'),
  ('life orientation',                   'life_orientation'),
  ('lewensoriëntering',                  'life_orientation'),
  ('geo',                                'geography'),
  ('geografie',                          'geography'),
  ('geskiedenis',                        'history'),
  ('physical science',                   'physical_sciences'),
  ('phys sci',                           'physical_sciences'),
  ('fisiese wetenskappe',                'physical_sciences'),
  ('tech sci',                           'technical_sciences'),
  ('technical science',                  'technical_sciences'),
  ('tegniese wetenskappe',               'technical_sciences'),
  ('life science',                       'life_sciences'),
  ('life sci',                           'life_sciences'),
  ('lewenswetenskappe',                  'life_sciences'),
  ('rekeningkunde',                      'accounting'),
  ('besigheidstudie',                    'business_studies'),
  ('besigheidstudies',                   'business_studies'),
  ('ekonomie',                           'economics'),
  ('verbruikerstudies',                  'consumer_studies'),
  ('gasvryheidstudies',                  'hospitality_studies'),
  ('toerisme',                           'tourism'),
  ('agri sci',                           'agricultural_sciences'),
  ('landbouwetenskappe',                 'agricultural_sciences'),
  ('amp',                                'agricultural_management_practices'),
  ('cat',                                'computer_applications_technology'),
  ('rtt',                                'computer_applications_technology'),
  ('it',                                 'information_technology'),
  ('inligtingstegnologie',               'information_technology'),
  ('egd',                                'engineering_graphics_and_design'),
  ('igo',                                'engineering_graphics_and_design'),
  ('dance',                              'dance_studies'),
  ('dansstudie',                         'dance_studies'),
  ('drama',                              'dramatic_arts'),
  ('dramatiese kunste',                  'dramatic_arts'),
  ('visuele kunste',                     'visual_arts'),
  ('godsdienstudie',                     'religion_studies'),
  ('rs',                                 'religion_studies'),
  ('telegu hl',                          'telugu_hl'),
  ('telegu fal',                         'telugu_fal'),
  ('telegu sal',                         'telugu_sal')
) as a(alias, k);

-- ---------------------------------------------------------------------
-- Career fields (hedged, plain-language notes: always "check current requirements")
-- ---------------------------------------------------------------------
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
   'Usually asks for strong Maths and Physical Sciences. Technical Mathematics and Technical Sciences open some routes, such as universities of technology and TVET colleges. Check each institution for current requirements.'),
  ('commerce_finance', 'Commerce and finance',
   'Accounting, auditing, economics, business and financial services.',
   'Requirements vary by programme, and some ask for Mathematics rather than Mathematical Literacy.');

insert into career_field_subjects (career_field_id, subject_id, weight)
select (select id from career_fields where key = m.field_key),
       (select id from subjects where key = m.subject_key),
       m.weight
from (values
  ('environmental_earth_sciences', 'geography',                       'core'),
  ('environmental_earth_sciences', 'life_sciences',                   'core'),
  ('environmental_earth_sciences', 'mathematics',                     'helpful'),
  ('environmental_earth_sciences', 'physical_sciences',               'helpful'),
  ('languages_law_media',          'english_hl',                      'core'),
  ('languages_law_media',          'afrikaans_fal',                   'helpful'),
  ('languages_law_media',          'history',                         'helpful'),
  ('health_sciences',              'life_sciences',                   'core'),
  ('health_sciences',              'mathematics',                     'core'),
  ('health_sciences',              'physical_sciences',               'core'),
  ('engineering_technology',       'mathematics',                     'core'),
  ('engineering_technology',       'physical_sciences',               'core'),
  ('engineering_technology',       'technical_mathematics',           'helpful'),
  ('engineering_technology',       'technical_sciences',              'helpful'),
  ('engineering_technology',       'engineering_graphics_and_design', 'helpful'),
  ('engineering_technology',       'information_technology',          'helpful'),
  ('commerce_finance',             'accounting',                      'core'),
  ('commerce_finance',             'economics',                       'core'),
  ('commerce_finance',             'mathematics',                     'helpful'),
  ('commerce_finance',             'business_studies',                'helpful')
) as m(field_key, subject_key, weight);
