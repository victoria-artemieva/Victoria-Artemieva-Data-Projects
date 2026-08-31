WITH users_clean AS (
/*В цій CTE уніфікуємо формат дати(signup_datetime):
 * 1) Додаємо нулі (lpad) для коректного формату дня або місяця DD.MM.YYYY, 
 * 2) to_date to_date перетворює текстовий рядок у значення типу date відповідно до заданого формату
 * 3) ::timestamp перетворює в тип timestamp*/
    SELECT
        user_id,
        promo_signup_flag,
        CASE
	        --перша гілка, що працює з форматом DD.MM.YYYY, якщо рік стоїть в третій частині та складається з 4х цифр
            WHEN split_part(clean_date, '.', 3) ~ '^\d{4}$' THEN 
                to_date(
                    lpad(split_part(clean_date, '.', 1), 2, '0') || '.' ||
                    lpad(split_part(clean_date, '.', 2), 2, '0') || '.' ||
                    split_part(clean_date, '.', 3),
                    'DD.MM.YYYY'
                )::timestamp
             --друга гілка, що працює з форматом DD.MM.YYYY, якщо рік стоїть в третій частині та складається з 2х цифр
            WHEN split_part(clean_date, '.', 3) ~ '^\d{2}$' THEN
                to_date(
                    lpad(split_part(clean_date, '.', 1), 2, '0') || '.' ||
                    lpad(split_part(clean_date, '.', 2), 2, '0') || '.' ||
                    '20' || split_part(clean_date, '.', 3),
                    'DD.MM.YYYY'
                )::timestamp
            ELSE NULL
        END AS signup_timestamp
        --в цій СТЕ прибираеємо зайві пробіли через trim та робимо єдиний формат дати (через крапку) за допомогою replace
        --за допомогою split_part залишаемо лише день, місяць, рік(без часу)
    FROM ( 
        SELECT
            user_id,
            promo_signup_flag,
            replace(
                replace(
                    split_part(trim(signup_datetime), ' ', 1),
                    '/',
                    '.'
                ),
                '-',
                '.'
            ) AS clean_date
        FROM cohort_users_raw
    ) t
),
/* Аналогічно очищаємо event_datetime з таблиці cohort_events_raw та приводимо його до єдиного типу timestamp */
events_clean AS (
    SELECT
        user_id,
        event_type,
        revenue,
        CASE
            WHEN split_part(clean_date, '.', 3) ~ '^\d{4}$' THEN
                to_date(
                    lpad(split_part(clean_date, '.', 1), 2, '0') || '.' ||
                    lpad(split_part(clean_date, '.', 2), 2, '0') || '.' ||
                    split_part(clean_date, '.', 3),
                    'DD.MM.YYYY'
                )::timestamp
            WHEN split_part(clean_date, '.', 3) ~ '^\d{2}$' THEN
                to_date(
                    lpad(split_part(clean_date, '.', 1), 2, '0') || '.' ||
                    lpad(split_part(clean_date, '.', 2), 2, '0') || '.' ||
                    '20' || split_part(clean_date, '.', 3),
                    'DD.MM.YYYY'
                )::timestamp
            ELSE NULL
        END AS event_timestamp
        FROM (
        SELECT
            user_id,
            event_type,
            revenue,
            replace(
                replace(
                    split_part(trim(event_datetime), ' ', 1),
                    '/',
                    '.'
                ),
                '-',
                '.'
            ) AS clean_date
        FROM cohort_events_raw
    ) t
),
/*В цій СТЕ:
 * 1) об'єднуємо users_clean та events_clean по user_id
 * 2) date_trunc('month', ...) обрізає дату до початку місяця 
 * 3) ::date прибирає часову частину 
 * 4) Щоб працювати з когортами знаходимо month_offset через extract(year...) та extract(month...), щоб дізнатись кількість місяців між реєстрацією та місяцем події
 * 5) Через WHERE фільтруємо дати, що мають увійти в нашу вибірку. (не NULL, не test_event, місяці між '2025-01-01' та '2025-06-01')*/ 
cohort_base AS (
    SELECT
        u.user_id,
        u.promo_signup_flag,
        date_trunc('month', u.signup_timestamp)::date AS cohort_month,
        date_trunc('month', e.event_timestamp)::date AS activity_month,
        (
            extract(year from age(date_trunc('month', e.event_timestamp), date_trunc('month', u.signup_timestamp))) * 12
            + extract(month from age(date_trunc('month', e.event_timestamp), date_trunc('month', u.signup_timestamp)))
        ) AS month_offset
    FROM users_clean u
    JOIN events_clean e
        ON u.user_id = e.user_id
    WHERE u.signup_timestamp IS NOT NULL
      AND e.event_timestamp IS NOT NULL
      AND e.event_type IS NOT NULL
      AND e.event_type <> 'test_event'
      AND date_trunc('month', e.event_timestamp)::date BETWEEN DATE '2025-01-01' AND DATE '2025-06-01'
)
/* Фінальний SELECT:
 * 1) Групуємо дані за promo_signup_flag, cohort_month та month_offset
 * 2) Рахуємо кількість унікальних користувачів
 * 3) Сортуємо результат для побудови когортної таблиці */
SELECT
    promo_signup_flag,
    cohort_month,
    month_offset,
    count(DISTINCT user_id) AS users_total
FROM cohort_base
GROUP BY
    promo_signup_flag,
    cohort_month,
    month_offset
ORDER BY
    promo_signup_flag,
    cohort_month,
    month_offset;