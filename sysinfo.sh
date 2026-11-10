set -o pipefail

SCRIPT_NAME=$(basename -- "$0")

ACTION_USERS=0
ACTION_PROCESSES=0
LOG_PATH=""
ERR_PATH=""

# ---------- вспомогательные функции ----------

# Сообщение об ошибке в стандартный поток ошибок
error_msg() {
    echo "$SCRIPT_NAME: ошибка: $*" >&2
}

# Запускает команду и обрабатывает её stderr: каждая строка получает
# префикс с именем скрипта и команды, пустые строки отбрасываются.
# Код возврата команды сохраняется.
run_filtered() {
    local err_file rc

    err_file=$(mktemp) || {
        error_msg "не удалось создать временный файл"
        return 1
    }
    "$@" 2>"$err_file"
    rc=$?
    if [[ -s $err_file ]]; then
        grep -v '^[[:space:]]*$' "$err_file" | sed "s|^|$SCRIPT_NAME: [$1] |" >&2
    fi
    rm -f "$err_file"
    return $rc
}

# Проверка пути для записи: $1 - путь, $2 - название аргумента
check_output_path() {
    local path=$1 what=$2 dir

    if [[ -z $path ]]; then
        error_msg "$what: путь не задан"
        return 1
    fi
    if [[ -d $path ]]; then
        error_msg "$what: '$path' является каталогом, а не файлом"
        return 1
    fi
    if [[ -e $path ]]; then
        if [[ ! -w $path ]]; then
            error_msg "$what: нет прав на запись в файл '$path'"
            return 1
        fi
    else
        dir=$(dirname -- "$path")
        if [[ ! -d $dir ]]; then
            error_msg "$what: каталог '$dir' не существует"
            return 1
        fi
        if [[ ! -w $dir || ! -x $dir ]]; then
            error_msg "$what: нет прав на создание файла в каталоге '$dir'"
            return 1
        fi
    fi
    return 0
}
# ---------- функции действий ----------

# -h, --help
print_help() {
    cat << HELP
Использование: $SCRIPT_NAME [ОПЦИИ]

Опции:
  -u, --users          вывести список пользователей и их домашних
                       каталогов, отсортированный по алфавиту
  -p, --processes      вывести список запущенных процессов,
                       отсортированный по идентификатору (PID)
  -h, --help           вывести эту справку и завершить работу
  -l, --log PATH       вместо вывода на экран писать вывод в файл PATH
  -e, --errors PATH    вместо вывода ошибок на экран писать их в файл PATH

Примеры:
  $SCRIPT_NAME -u
  $SCRIPT_NAME --processes --log /tmp/processes.txt
  $SCRIPT_NAME -u -p -l out.txt -e err.txt
HELP
}

# -u, --users
show_users() {
    echo "Пользователи и домашние каталоги (по алфавиту):"
    if ! run_filtered getent passwd | awk -F: '{ printf "%-20s %s\n", $1, $6 }' | sort -k1,1; then
        error_msg "не удалось получить список пользователей"
        return 1
    fi
}

# -p, --processes
show_processes() {
    echo "Запущенные процессы (по возрастанию PID):"
    if ! run_filtered ps -eo pid,user,comm --sort=pid; then
        error_msg "не удалось получить список процессов"
        return 1
    fi
}

# -l, --log
redirect_output() {
    exec >"$LOG_PATH"
}

# -e, --errors
redirect_errors() {
    exec 2>"$ERR_PATH"
}
# ---------- разбор аргументов ----------

PARSED=$(run_filtered getopt -o uphl:e: --long users,processes,help,log:,errors: \
         -n "$SCRIPT_NAME" -- "$@") || {
    echo "Для справки используйте: $SCRIPT_NAME --help" >&2
    exit 2
}
eval set -- "$PARSED"

while true; do
    case "$1" in
        -u|--users)     ACTION_USERS=1;     shift ;;
        -p|--processes) ACTION_PROCESSES=1; shift ;;
        -h|--help)      print_help; exit 0 ;;
        -l|--log)       LOG_PATH=$2;        shift 2 ;;
        -e|--errors)    ERR_PATH=$2;        shift 2 ;;
        --)             shift; break ;;
        *)              error_msg "внутренняя ошибка разбора аргументов"; exit 2 ;;
    esac
done

if [[ $# -gt 0 ]]; then
    error_msg "лишние аргументы: $*"
    echo "Для справки используйте: $SCRIPT_NAME --help" >&2
    exit 2
fi

if [[ $ACTION_USERS -eq 0 && $ACTION_PROCESSES -eq 0 ]]; then
    error_msg "не указано действие (-u или -p)"
    echo "Для справки используйте: $SCRIPT_NAME --help" >&2
    exit 2
fi

# ---------- проверка путей и перенаправление ----------

# Сначала проверяем оба пути (сообщения идут на экран), потом перенаправляем
[[ -n $LOG_PATH ]] && { check_output_path "$LOG_PATH" "-l/--log" || exit 1; }
[[ -n $ERR_PATH ]] && { check_output_path "$ERR_PATH" "-e/--errors" || exit 1; }

if [[ -n $ERR_PATH ]]; then
    redirect_errors || exit 1
fi
if [[ -n $LOG_PATH ]]; then
    if [[ $LOG_PATH == "$ERR_PATH" ]]; then
        exec >&2          # оба потока в один и тот же файл
    else
        redirect_output || exit 1
    fi
fi

# ---------- выполнение действий ----------

status=0
if [[ $ACTION_USERS -eq 1 ]]; then
    show_users || status=1
fi
if [[ $ACTION_PROCESSES -eq 1 ]]; then
    [[ $ACTION_USERS -eq 1 ]] && echo
    show_processes || status=1
fi

exit $status
