/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison implementation for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* C LALR(1) parser skeleton written by Richard Stallman, by
   simplifying the original so-called "semantic" parser.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output, and Bison version.  */
#define YYBISON 30802

/* Bison version string.  */
#define YYBISON_VERSION "3.8.2"

/* Skeleton name.  */
#define YYSKELETON_NAME "yacc.c"

/* Pure parsers.  */
#define YYPURE 1

/* Push parsers.  */
#define YYPUSH 0

/* Pull parsers.  */
#define YYPULL 1

/* Substitute the type names.  */
#define YYSTYPE         HB_MACRO_YYSTYPE
/* Substitute the variable and function names.  */
#define yyparse         hb_macro_yyparse
#define yylex           hb_macro_yylex
#define yyerror         hb_macro_yyerror
#define yydebug         hb_macro_yydebug
#define yynerrs         hb_macro_yynerrs

/* First part of user prologue.  */
#line 6 "c:\\temp\\harbour-core\\src\\macro\\macro.y"

/*
 * Macro compiler YACC rules and actions
 *
 * Copyright 1999 Antonio Linares <alinares@fivetech.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file LICENSE.txt.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA (or visit https://www.gnu.org/licenses/).
 *
 * As a special exception, the Harbour Project gives permission for
 * additional uses of the text contained in its release of Harbour.
 *
 * The exception is that, if you link the Harbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the Harbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the Harbour
 * Project under the name Harbour.  If you copy code from other
 * Harbour Project or Free Software Foundation releases into a copy of
 * Harbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for Harbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

/* TODO list
 * 1) Change the pcode generated by ::cVar from Self:cVar to QSELF():cVar
 *    The major problem to solve is how to support QSELF() inside a codeblock.
 */

/* this #define HAVE TO be placed before all #include directives
 */
#define  HB_MACRO_SUPPORT

#include "hbmacro.h"
#include "hbcomp.h"
#include "hbdate.h"
#include "hbpp.h"

/* Compile using: bison -d -p hb_comp macro.y */

/* to pacify some meaningless warnings */
#if defined( __BORLANDC__ )
#  if ! defined( __STDC__ )
#     define __STDC__
#  endif
#  pragma warn -aus
#  pragma warn -ccc
#  pragma warn -rch
#elif defined( __WATCOMC__ ) && defined( __cplusplus )
#  pragma warning 13 9
#  pragma warning 368 9
#elif defined( _MSC_VER )
#  pragma warning( disable : 4244 )
#  pragma warning( disable : 4702 )
#endif

#undef alloca
#define alloca  hb_xgrab
#undef malloc
#define malloc  hb_xgrab
#undef realloc
#define realloc hb_xrealloc
#undef free
#define free    hb_xfree

/* NOTE: these symbols are used internally in bison.simple
 */
#undef YYFREE
#define YYFREE hb_xfree
#undef YYMALLOC
#define YYMALLOC hb_xgrab

#define NO_YYERROR

/* NOTE: these symbols are defined explicitly to pacify warnings */
#define YYENABLE_NLS          0
#define YYLTYPE_IS_TRIVIAL    0


/* yacc/lex related definitions
 */


/* Standard checking for valid expression creation
 */
#define HB_MACRO_CHECK( pExpr ) \
   if( ! ( HB_MACRO_DATA->status & HB_MACRO_CONT ) ) \
   { \
      YYABORT; \
   }

#define HB_MACRO_IFENABLED( pSet, pExpr, flag ) \
   if( HB_MACRO_DATA->supported & ( flag ) ) \
   { \
      pSet = ( pExpr ); \
   }\
   else \
   { \
      YYABORT; \
   }

#if defined( __BORLANDC__ ) || defined( __WATCOMC__ )
/* The if() inside this macro is always TRUE but it's used to hide BCC warning */
#define HB_MACRO_ABORT if( !( HB_MACRO_DATA->status & HB_MACRO_CONT ) ) { YYABORT; }
#else
#define HB_MACRO_ABORT { YYABORT; }
#endif


#line 210 "macroy.c"

# ifndef YY_CAST
#  ifdef __cplusplus
#   define YY_CAST(Type, Val) static_cast<Type> (Val)
#   define YY_REINTERPRET_CAST(Type, Val) reinterpret_cast<Type> (Val)
#  else
#   define YY_CAST(Type, Val) ((Type) (Val))
#   define YY_REINTERPRET_CAST(Type, Val) ((Type) (Val))
#  endif
# endif
# ifndef YY_NULLPTR
#  if defined __cplusplus
#   if 201103L <= __cplusplus
#    define YY_NULLPTR nullptr
#   else
#    define YY_NULLPTR 0
#   endif
#  else
#   define YY_NULLPTR ((void*)0)
#  endif
# endif

#include "macroy.h"
/* Symbol kind.  */
enum yysymbol_kind_t
{
  YYSYMBOL_YYEMPTY = -2,
  YYSYMBOL_YYEOF = 0,                      /* "end of file"  */
  YYSYMBOL_YYerror = 1,                    /* error  */
  YYSYMBOL_YYUNDEF = 2,                    /* "invalid token"  */
  YYSYMBOL_IDENTIFIER = 3,                 /* IDENTIFIER  */
  YYSYMBOL_NIL = 4,                        /* NIL  */
  YYSYMBOL_NUM_DOUBLE = 5,                 /* NUM_DOUBLE  */
  YYSYMBOL_INASSIGN = 6,                   /* INASSIGN  */
  YYSYMBOL_NUM_LONG = 7,                   /* NUM_LONG  */
  YYSYMBOL_NUM_DATE = 8,                   /* NUM_DATE  */
  YYSYMBOL_TIMESTAMP = 9,                  /* TIMESTAMP  */
  YYSYMBOL_IIF = 10,                       /* IIF  */
  YYSYMBOL_LITERAL = 11,                   /* LITERAL  */
  YYSYMBOL_TRUEVALUE = 12,                 /* TRUEVALUE  */
  YYSYMBOL_FALSEVALUE = 13,                /* FALSEVALUE  */
  YYSYMBOL_AND = 14,                       /* AND  */
  YYSYMBOL_OR = 15,                        /* OR  */
  YYSYMBOL_NOT = 16,                       /* NOT  */
  YYSYMBOL_EQ = 17,                        /* EQ  */
  YYSYMBOL_NE1 = 18,                       /* NE1  */
  YYSYMBOL_NE2 = 19,                       /* NE2  */
  YYSYMBOL_INC = 20,                       /* INC  */
  YYSYMBOL_DEC = 21,                       /* DEC  */
  YYSYMBOL_ALIASOP = 22,                   /* ALIASOP  */
  YYSYMBOL_HASHOP = 23,                    /* HASHOP  */
  YYSYMBOL_SELF = 24,                      /* SELF  */
  YYSYMBOL_LE = 25,                        /* LE  */
  YYSYMBOL_GE = 26,                        /* GE  */
  YYSYMBOL_FIELD = 27,                     /* FIELD  */
  YYSYMBOL_MACROVAR = 28,                  /* MACROVAR  */
  YYSYMBOL_MACROTEXT = 29,                 /* MACROTEXT  */
  YYSYMBOL_PLUSEQ = 30,                    /* PLUSEQ  */
  YYSYMBOL_MINUSEQ = 31,                   /* MINUSEQ  */
  YYSYMBOL_MULTEQ = 32,                    /* MULTEQ  */
  YYSYMBOL_DIVEQ = 33,                     /* DIVEQ  */
  YYSYMBOL_POWER = 34,                     /* POWER  */
  YYSYMBOL_EXPEQ = 35,                     /* EXPEQ  */
  YYSYMBOL_MODEQ = 36,                     /* MODEQ  */
  YYSYMBOL_EPSILON = 37,                   /* EPSILON  */
  YYSYMBOL_POST = 38,                      /* POST  */
  YYSYMBOL_39_ = 39,                       /* '='  */
  YYSYMBOL_40_ = 40,                       /* '<'  */
  YYSYMBOL_41_ = 41,                       /* '>'  */
  YYSYMBOL_42_ = 42,                       /* '$'  */
  YYSYMBOL_43_ = 43,                       /* '+'  */
  YYSYMBOL_44_ = 44,                       /* '-'  */
  YYSYMBOL_45_ = 45,                       /* '*'  */
  YYSYMBOL_46_ = 46,                       /* '/'  */
  YYSYMBOL_47_ = 47,                       /* '%'  */
  YYSYMBOL_UNARY = 48,                     /* UNARY  */
  YYSYMBOL_PRE = 49,                       /* PRE  */
  YYSYMBOL_50_ = 50,                       /* '&'  */
  YYSYMBOL_51_ = 51,                       /* '@'  */
  YYSYMBOL_52_ = 52,                       /* ','  */
  YYSYMBOL_53_ = 53,                       /* '{'  */
  YYSYMBOL_54_ = 54,                       /* '}'  */
  YYSYMBOL_55_ = 55,                       /* '('  */
  YYSYMBOL_56_ = 56,                       /* ')'  */
  YYSYMBOL_57_ = 57,                       /* ':'  */
  YYSYMBOL_58_ = 58,                       /* ']'  */
  YYSYMBOL_59_ = 59,                       /* '['  */
  YYSYMBOL_60_ = 60,                       /* '|'  */
  YYSYMBOL_YYACCEPT = 61,                  /* $accept  */
  YYSYMBOL_Main = 62,                      /* Main  */
  YYSYMBOL_NumValue = 63,                  /* NumValue  */
  YYSYMBOL_DateValue = 64,                 /* DateValue  */
  YYSYMBOL_TimeStampValue = 65,            /* TimeStampValue  */
  YYSYMBOL_NumAlias = 66,                  /* NumAlias  */
  YYSYMBOL_NilValue = 67,                  /* NilValue  */
  YYSYMBOL_LiteralValue = 68,              /* LiteralValue  */
  YYSYMBOL_Logical = 69,                   /* Logical  */
  YYSYMBOL_SelfValue = 70,                 /* SelfValue  */
  YYSYMBOL_Array = 71,                     /* Array  */
  YYSYMBOL_ArrayAt = 72,                   /* ArrayAt  */
  YYSYMBOL_Hash = 73,                      /* Hash  */
  YYSYMBOL_HashList = 74,                  /* HashList  */
  YYSYMBOL_Variable = 75,                  /* Variable  */
  YYSYMBOL_VarAlias = 76,                  /* VarAlias  */
  YYSYMBOL_MacroVar = 77,                  /* MacroVar  */
  YYSYMBOL_MacroVarAlias = 78,             /* MacroVarAlias  */
  YYSYMBOL_MacroExpr = 79,                 /* MacroExpr  */
  YYSYMBOL_MacroExprAlias = 80,            /* MacroExprAlias  */
  YYSYMBOL_FieldAlias = 81,                /* FieldAlias  */
  YYSYMBOL_FieldVarAlias = 82,             /* FieldVarAlias  */
  YYSYMBOL_AliasId = 83,                   /* AliasId  */
  YYSYMBOL_AliasVar = 84,                  /* AliasVar  */
  YYSYMBOL_AliasExpr = 85,                 /* AliasExpr  */
  YYSYMBOL_VariableAt = 86,                /* VariableAt  */
  YYSYMBOL_FunCall = 87,                   /* FunCall  */
  YYSYMBOL_FunRef = 88,                    /* FunRef  */
  YYSYMBOL_ArgList = 89,                   /* ArgList  */
  YYSYMBOL_Argument = 90,                  /* Argument  */
  YYSYMBOL_RefArgument = 91,               /* RefArgument  */
  YYSYMBOL_ExtArgument = 92,               /* ExtArgument  */
  YYSYMBOL_ObjectData = 93,                /* ObjectData  */
  YYSYMBOL_SendId = 94,                    /* SendId  */
  YYSYMBOL_ObjectMethod = 95,              /* ObjectMethod  */
  YYSYMBOL_SimpleExpression = 96,          /* SimpleExpression  */
  YYSYMBOL_Expression = 97,                /* Expression  */
  YYSYMBOL_ExtExpression = 98,             /* ExtExpression  */
  YYSYMBOL_RootParamList = 99,             /* RootParamList  */
  YYSYMBOL_100_1 = 100,                    /* $@1  */
  YYSYMBOL_AsParamList = 101,              /* AsParamList  */
  YYSYMBOL_EmptyExpression = 102,          /* EmptyExpression  */
  YYSYMBOL_LeftExpression = 103,           /* LeftExpression  */
  YYSYMBOL_PostOp = 104,                   /* PostOp  */
  YYSYMBOL_ExprPostOp = 105,               /* ExprPostOp  */
  YYSYMBOL_ExprPreOp = 106,                /* ExprPreOp  */
  YYSYMBOL_ExprUnary = 107,                /* ExprUnary  */
  YYSYMBOL_ExprAssign = 108,               /* ExprAssign  */
  YYSYMBOL_ExprPlusEq = 109,               /* ExprPlusEq  */
  YYSYMBOL_ExprMinusEq = 110,              /* ExprMinusEq  */
  YYSYMBOL_ExprMultEq = 111,               /* ExprMultEq  */
  YYSYMBOL_ExprDivEq = 112,                /* ExprDivEq  */
  YYSYMBOL_ExprModEq = 113,                /* ExprModEq  */
  YYSYMBOL_ExprExpEq = 114,                /* ExprExpEq  */
  YYSYMBOL_ExprOperEq = 115,               /* ExprOperEq  */
  YYSYMBOL_ExprMath = 116,                 /* ExprMath  */
  YYSYMBOL_ExprBool = 117,                 /* ExprBool  */
  YYSYMBOL_ExprRelation = 118,             /* ExprRelation  */
  YYSYMBOL_ArrayIndex = 119,               /* ArrayIndex  */
  YYSYMBOL_IndexList = 120,                /* IndexList  */
  YYSYMBOL_ElemList = 121,                 /* ElemList  */
  YYSYMBOL_CodeBlock = 122,                /* CodeBlock  */
  YYSYMBOL_123_2 = 123,                    /* @2  */
  YYSYMBOL_BlockExpList = 124,             /* BlockExpList  */
  YYSYMBOL_BlockVars = 125,                /* BlockVars  */
  YYSYMBOL_BlockVarList = 126,             /* BlockVarList  */
  YYSYMBOL_ExpList = 127,                  /* ExpList  */
  YYSYMBOL_PareExpList = 128,              /* PareExpList  */
  YYSYMBOL_PareExpListAlias = 129,         /* PareExpListAlias  */
  YYSYMBOL_IfInline = 130                  /* IfInline  */
};
typedef enum yysymbol_kind_t yysymbol_kind_t;


/* Second part of user prologue.  */
#line 173 "c:\\temp\\harbour-core\\src\\macro\\macro.y"

/* This must be placed after the above union - the union is
 * typedef-ined to YYSTYPE
 */
extern int  yylex( YYSTYPE *, PHB_MACRO );   /* main lex token function, called by yyparse() */
extern int  yyparse( PHB_MACRO );            /* main yacc parsing function */
extern void yyerror( PHB_MACRO, const char * );    /* parsing error management function */


#line 384 "macroy.c"


#ifdef short
# undef short
#endif

/* On compilers that do not define __PTRDIFF_MAX__ etc., make sure
   <limits.h> and (if available) <stdint.h> are included
   so that the code can choose integer types of a good width.  */

#ifndef __PTRDIFF_MAX__
# include <limits.h> /* INFRINGES ON USER NAME SPACE */
# if defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stdint.h> /* INFRINGES ON USER NAME SPACE */
#  define YY_STDINT_H
# endif
#endif

/* Narrow types that promote to a signed type and that can represent a
   signed or unsigned integer of at least N bits.  In tables they can
   save space and decrease cache pressure.  Promoting to a signed type
   helps avoid bugs in integer arithmetic.  */

#ifdef __INT_LEAST8_MAX__
typedef __INT_LEAST8_TYPE__ yytype_int8;
#elif defined YY_STDINT_H
typedef int_least8_t yytype_int8;
#else
typedef signed char yytype_int8;
#endif

#ifdef __INT_LEAST16_MAX__
typedef __INT_LEAST16_TYPE__ yytype_int16;
#elif defined YY_STDINT_H
typedef int_least16_t yytype_int16;
#else
typedef short yytype_int16;
#endif

/* Work around bug in HP-UX 11.23, which defines these macros
   incorrectly for preprocessor constants.  This workaround can likely
   be removed in 2023, as HPE has promised support for HP-UX 11.23
   (aka HP-UX 11i v2) only through the end of 2022; see Table 2 of
   <https://h20195.www2.hpe.com/V2/getpdf.aspx/4AA4-7673ENW.pdf>.  */
#ifdef __hpux
# undef UINT_LEAST8_MAX
# undef UINT_LEAST16_MAX
# define UINT_LEAST8_MAX 255
# define UINT_LEAST16_MAX 65535
#endif

#if defined __UINT_LEAST8_MAX__ && __UINT_LEAST8_MAX__ <= __INT_MAX__
typedef __UINT_LEAST8_TYPE__ yytype_uint8;
#elif (!defined __UINT_LEAST8_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST8_MAX <= INT_MAX)
typedef uint_least8_t yytype_uint8;
#elif !defined __UINT_LEAST8_MAX__ && UCHAR_MAX <= INT_MAX
typedef unsigned char yytype_uint8;
#else
typedef short yytype_uint8;
#endif

#if defined __UINT_LEAST16_MAX__ && __UINT_LEAST16_MAX__ <= __INT_MAX__
typedef __UINT_LEAST16_TYPE__ yytype_uint16;
#elif (!defined __UINT_LEAST16_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST16_MAX <= INT_MAX)
typedef uint_least16_t yytype_uint16;
#elif !defined __UINT_LEAST16_MAX__ && USHRT_MAX <= INT_MAX
typedef unsigned short yytype_uint16;
#else
typedef int yytype_uint16;
#endif

#ifndef YYPTRDIFF_T
# if defined __PTRDIFF_TYPE__ && defined __PTRDIFF_MAX__
#  define YYPTRDIFF_T __PTRDIFF_TYPE__
#  define YYPTRDIFF_MAXIMUM __PTRDIFF_MAX__
# elif defined PTRDIFF_MAX
#  ifndef ptrdiff_t
#   include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  endif
#  define YYPTRDIFF_T ptrdiff_t
#  define YYPTRDIFF_MAXIMUM PTRDIFF_MAX
# else
#  define YYPTRDIFF_T long
#  define YYPTRDIFF_MAXIMUM LONG_MAX
# endif
#endif

#ifndef YYSIZE_T
# ifdef __SIZE_TYPE__
#  define YYSIZE_T __SIZE_TYPE__
# elif defined size_t
#  define YYSIZE_T size_t
# elif defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# else
#  define YYSIZE_T unsigned
# endif
#endif

#define YYSIZE_MAXIMUM                                  \
  YY_CAST (YYPTRDIFF_T,                                 \
           (YYPTRDIFF_MAXIMUM < YY_CAST (YYSIZE_T, -1)  \
            ? YYPTRDIFF_MAXIMUM                         \
            : YY_CAST (YYSIZE_T, -1)))

#define YYSIZEOF(X) YY_CAST (YYPTRDIFF_T, sizeof (X))


/* Stored state numbers (used for stacks). */
typedef yytype_int16 yy_state_t;

/* State numbers in computations.  */
typedef int yy_state_fast_t;

#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> /* INFRINGES ON USER NAME SPACE */
#   define YY_(Msgid) dgettext ("bison-runtime", Msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(Msgid) Msgid
# endif
#endif


#ifndef YY_ATTRIBUTE_PURE
# if defined __GNUC__ && 2 < __GNUC__ + (96 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_PURE __attribute__ ((__pure__))
# else
#  define YY_ATTRIBUTE_PURE
# endif
#endif

#ifndef YY_ATTRIBUTE_UNUSED
# if defined __GNUC__ && 2 < __GNUC__ + (7 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_UNUSED __attribute__ ((__unused__))
# else
#  define YY_ATTRIBUTE_UNUSED
# endif
#endif

/* Suppress unused-variable warnings by "using" E.  */
#if ! defined lint || defined __GNUC__
# define YY_USE(E) ((void) (E))
#else
# define YY_USE(E) /* empty */
#endif

/* Suppress an incorrect diagnostic about yylval being uninitialized.  */
#if defined __GNUC__ && ! defined __ICC && 406 <= __GNUC__ * 100 + __GNUC_MINOR__
# if __GNUC__ * 100 + __GNUC_MINOR__ < 407
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")
# else
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")              \
    _Pragma ("GCC diagnostic ignored \"-Wmaybe-uninitialized\"")
# endif
# define YY_IGNORE_MAYBE_UNINITIALIZED_END      \
    _Pragma ("GCC diagnostic pop")
#else
# define YY_INITIAL_VALUE(Value) Value
#endif
#ifndef YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_END
#endif
#ifndef YY_INITIAL_VALUE
# define YY_INITIAL_VALUE(Value) /* Nothing. */
#endif

#if defined __cplusplus && defined __GNUC__ && ! defined __ICC && 6 <= __GNUC__
# define YY_IGNORE_USELESS_CAST_BEGIN                          \
    _Pragma ("GCC diagnostic push")                            \
    _Pragma ("GCC diagnostic ignored \"-Wuseless-cast\"")
# define YY_IGNORE_USELESS_CAST_END            \
    _Pragma ("GCC diagnostic pop")
#endif
#ifndef YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_END
#endif


#define YY_ASSERT(E) ((void) (0 && (E)))

#if !defined yyoverflow

/* The parser invokes alloca or malloc; define the necessary symbols.  */

# ifdef YYSTACK_USE_ALLOCA
#  if YYSTACK_USE_ALLOCA
#   ifdef __GNUC__
#    define YYSTACK_ALLOC __builtin_alloca
#   elif defined __BUILTIN_VA_ARG_INCR
#    include <alloca.h> /* INFRINGES ON USER NAME SPACE */
#   elif defined _AIX
#    define YYSTACK_ALLOC __alloca
#   elif defined _MSC_VER
#    include <malloc.h> /* INFRINGES ON USER NAME SPACE */
#    define alloca _alloca
#   else
#    define YYSTACK_ALLOC alloca
#    if ! defined _ALLOCA_H && ! defined EXIT_SUCCESS
#     include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
      /* Use EXIT_SUCCESS as a witness for stdlib.h.  */
#     ifndef EXIT_SUCCESS
#      define EXIT_SUCCESS 0
#     endif
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's 'empty if-body' warning.  */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (0)
#  ifndef YYSTACK_ALLOC_MAXIMUM
    /* The OS might guarantee only one guard page at the bottom of the stack,
       and a page size can be as small as 4096 bytes.  So we cannot safely
       invoke alloca (N) if N exceeds 4096.  Use a slightly smaller number
       to allow for a few compiler-allocated temporary stack slots.  */
#   define YYSTACK_ALLOC_MAXIMUM 4032 /* reasonable circa 2006 */
#  endif
# else
#  define YYSTACK_ALLOC YYMALLOC
#  define YYSTACK_FREE YYFREE
#  ifndef YYSTACK_ALLOC_MAXIMUM
#   define YYSTACK_ALLOC_MAXIMUM YYSIZE_MAXIMUM
#  endif
#  if (defined __cplusplus && ! defined EXIT_SUCCESS \
       && ! ((defined YYMALLOC || defined malloc) \
             && (defined YYFREE || defined free)))
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   ifndef EXIT_SUCCESS
#    define EXIT_SUCCESS 0
#   endif
#  endif
#  ifndef YYMALLOC
#   define YYMALLOC malloc
#   if ! defined malloc && ! defined EXIT_SUCCESS
void *malloc (YYSIZE_T); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
#  ifndef YYFREE
#   define YYFREE free
#   if ! defined free && ! defined EXIT_SUCCESS
void free (void *); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
# endif
#endif /* !defined yyoverflow */

#if (! defined yyoverflow \
     && (! defined __cplusplus \
         || (defined HB_MACRO_YYSTYPE_IS_TRIVIAL && HB_MACRO_YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  yy_state_t yyss_alloc;
  YYSTYPE yyvs_alloc;
};

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAXIMUM (YYSIZEOF (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (YYSIZEOF (yy_state_t) + YYSIZEOF (YYSTYPE)) \
      + YYSTACK_GAP_MAXIMUM)

# define YYCOPY_NEEDED 1

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack_alloc, Stack)                           \
    do                                                                  \
      {                                                                 \
        YYPTRDIFF_T yynewbytes;                                         \
        YYCOPY (&yyptr->Stack_alloc, Stack, yysize);                    \
        Stack = &yyptr->Stack_alloc;                                    \
        yynewbytes = yystacksize * YYSIZEOF (*Stack) + YYSTACK_GAP_MAXIMUM; \
        yyptr += yynewbytes / YYSIZEOF (*yyptr);                        \
      }                                                                 \
    while (0)

#endif

#if defined YYCOPY_NEEDED && YYCOPY_NEEDED
/* Copy COUNT objects from SRC to DST.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if defined __GNUC__ && 1 < __GNUC__
#   define YYCOPY(Dst, Src, Count) \
      __builtin_memcpy (Dst, Src, YY_CAST (YYSIZE_T, (Count)) * sizeof (*(Src)))
#  else
#   define YYCOPY(Dst, Src, Count)              \
      do                                        \
        {                                       \
          YYPTRDIFF_T yyi;                      \
          for (yyi = 0; yyi < (Count); yyi++)   \
            (Dst)[yyi] = (Src)[yyi];            \
        }                                       \
      while (0)
#  endif
# endif
#endif /* !YYCOPY_NEEDED */

/* YYFINAL -- State number of the termination state.  */
#define YYFINAL  102
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   1272

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  61
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  70
/* YYNRULES -- Number of rules.  */
#define YYNRULES  208
/* YYNSTATES -- Number of states.  */
#define YYNSTATES  298

/* YYMAXUTOK -- Last valid token kind.  */
#define YYMAXUTOK   295


/* YYTRANSLATE(TOKEN-NUM) -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex, with out-of-bounds checking.  */
#define YYTRANSLATE(YYX)                                \
  (0 <= (YYX) && (YYX) <= YYMAXUTOK                     \
   ? YY_CAST (yysymbol_kind_t, yytranslate[YYX])        \
   : YYSYMBOL_YYUNDEF)

/* YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex.  */
static const yytype_int8 yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,    42,    47,    50,     2,
      55,    56,    45,    43,    52,    44,     2,    46,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    57,     2,
      40,    39,    41,     2,    51,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    59,     2,    58,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    53,    60,    54,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      35,    36,    37,    38,    48,    49
};

#if HB_MACRO_YYDEBUG
/* YYRLINE[YYN] -- Source line where rule number YYN was defined.  */
static const yytype_int16 yyrline[] =
{
       0,   257,   257,   267,   275,   284,   285,   288,   291,   294,
     299,   304,   309,   310,   315,   320,   325,   330,   331,   334,
     335,   341,   344,   349,   352,   371,   376,   379,   386,   387,
     392,   393,   394,   395,   396,   399,   400,   401,   404,   405,
     406,   407,   408,   409,   410,   419,   420,   421,   422,   423,
     428,   429,   430,   431,   432,   433,   434,   435,   436,   437,
     438,   439,   440,   441,   442,   443,   444,   445,   446,   451,
     454,   459,   469,   470,   473,   474,   477,   478,   479,   480,
     481,   484,   485,   490,   493,   494,   495,   500,   504,   505,
     506,   507,   508,   509,   510,   511,   512,   513,   514,   515,
     516,   517,   518,   519,   520,   521,   522,   523,   524,   525,
     526,   527,   528,   529,   530,   531,   532,   533,   536,   537,
     540,   541,   544,   544,   558,   559,   563,   564,   567,   568,
     569,   570,   571,   572,   573,   574,   575,   576,   577,   578,
     579,   580,   581,   582,   583,   584,   585,   586,   587,   588,
     594,   595,   601,   604,   605,   608,   609,   610,   613,   616,
     619,   622,   625,   628,   631,   634,   635,   636,   637,   638,
     639,   642,   643,   644,   645,   646,   647,   650,   651,   654,
     655,   656,   657,   658,   659,   660,   661,   662,   665,   671,
     672,   673,   676,   677,   681,   680,   688,   689,   694,   695,
     696,   697,   700,   701,   704,   705,   708,   711,   715
};
#endif

/** Accessing symbol of state STATE.  */
#define YY_ACCESSING_SYMBOL(State) YY_CAST (yysymbol_kind_t, yystos[State])

#if HB_MACRO_YYDEBUG || 0
/* The user-facing name of the symbol whose (internal) number is
   YYSYMBOL.  No bounds checking.  */
static const char *yysymbol_name (yysymbol_kind_t yysymbol) YY_ATTRIBUTE_UNUSED;

/* YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals.  */
static const char *const yytname[] =
{
  "\"end of file\"", "error", "\"invalid token\"", "IDENTIFIER", "NIL",
  "NUM_DOUBLE", "INASSIGN", "NUM_LONG", "NUM_DATE", "TIMESTAMP", "IIF",
  "LITERAL", "TRUEVALUE", "FALSEVALUE", "AND", "OR", "NOT", "EQ", "NE1",
  "NE2", "INC", "DEC", "ALIASOP", "HASHOP", "SELF", "LE", "GE", "FIELD",
  "MACROVAR", "MACROTEXT", "PLUSEQ", "MINUSEQ", "MULTEQ", "DIVEQ", "POWER",
  "EXPEQ", "MODEQ", "EPSILON", "POST", "'='", "'<'", "'>'", "'$'", "'+'",
  "'-'", "'*'", "'/'", "'%'", "UNARY", "PRE", "'&'", "'@'", "','", "'{'",
  "'}'", "'('", "')'", "':'", "']'", "'['", "'|'", "$accept", "Main",
  "NumValue", "DateValue", "TimeStampValue", "NumAlias", "NilValue",
  "LiteralValue", "Logical", "SelfValue", "Array", "ArrayAt", "Hash",
  "HashList", "Variable", "VarAlias", "MacroVar", "MacroVarAlias",
  "MacroExpr", "MacroExprAlias", "FieldAlias", "FieldVarAlias", "AliasId",
  "AliasVar", "AliasExpr", "VariableAt", "FunCall", "FunRef", "ArgList",
  "Argument", "RefArgument", "ExtArgument", "ObjectData", "SendId",
  "ObjectMethod", "SimpleExpression", "Expression", "ExtExpression",
  "RootParamList", "$@1", "AsParamList", "EmptyExpression",
  "LeftExpression", "PostOp", "ExprPostOp", "ExprPreOp", "ExprUnary",
  "ExprAssign", "ExprPlusEq", "ExprMinusEq", "ExprMultEq", "ExprDivEq",
  "ExprModEq", "ExprExpEq", "ExprOperEq", "ExprMath", "ExprBool",
  "ExprRelation", "ArrayIndex", "IndexList", "ElemList", "CodeBlock", "@2",
  "BlockExpList", "BlockVars", "BlockVarList", "ExpList", "PareExpList",
  "PareExpListAlias", "IfInline", YY_NULLPTR
};

static const char *
yysymbol_name (yysymbol_kind_t yysymbol)
{
  return yytname[yysymbol];
}
#endif

#define YYPACT_NINF (-260)

#define yypact_value_is_default(Yyn) \
  ((Yyn) == YYPACT_NINF)

#define YYTABLE_NINF (-150)

#define yytable_value_is_error(Yyn) \
  0

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
static const yytype_int16 yypact[] =
{
     346,  -260,   -15,  -260,  -260,   -12,  -260,  -260,   -38,  -260,
    -260,  -260,   843,   843,   843,  -260,    -4,  -260,  -260,   843,
     843,   -31,    32,   288,   843,    42,   437,   454,   471,     5,
     489,   506,   523,   541,   558,   959,   575,   593,     5,   172,
       5,   372,     5,     2,     8,   610,   627,   976,   645,  -260,
     389,   662,  -260,  1020,  -260,    15,    30,   994,  -260,  -260,
    -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,
    -260,  -260,   679,    70,   406,     5,   697,  -260,   737,  -260,
     843,  1225,  -260,  -260,    58,  -260,  -260,  -260,    -7,    14,
    -260,   949,  -260,    46,  -260,  -260,  -260,  1092,  -260,    87,
    1160,  -260,  -260,   790,  -260,   -37,  -260,  -260,  -260,  -260,
    -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,
    -260,  -260,  -260,   737,  -260,  -260,  -260,  -260,  -260,  -260,
    -260,    51,   -12,  -260,  -260,    77,  -260,    83,  -260,  -260,
      88,  -260,  -260,  -260,  -260,  -260,   737,  -260,  -260,   843,
     843,   843,   843,   843,   843,   843,   843,   843,   843,   843,
     843,   843,   843,   843,   843,   843,   843,  -260,   843,  -260,
    -260,   843,   843,   843,   843,   843,   843,    41,  -260,  -260,
     843,  -260,  -260,  -260,  -260,  -260,  -260,    73,  -260,  1056,
    -260,   737,  -260,    -6,    64,    64,    64,    64,    64,    64,
      64,    64,  -260,    64,    64,    17,     7,   138,    64,    90,
      64,    22,    64,    91,    64,    16,    64,    19,   843,  -260,
     843,   737,  -260,  -260,  1160,  -260,   790,    68,    84,   127,
    1194,  1160,  1225,  1225,  1225,   835,   835,   100,  1225,   835,
     835,   835,    74,    74,    97,    97,    97,  -260,   843,  1160,
    1160,  1160,  1160,  1160,  1160,  1160,  -260,  -260,  -260,  -260,
    -260,   737,  -260,   896,   132,   737,  -260,  -260,   106,   117,
    1126,  -260,  -260,  -260,   790,  -260,  -260,  -260,  -260,   125,
    -260,   133,   843,    25,   843,  -260,   896,   142,  1160,   157,
    -260,  -260,  -260,   126,   843,  -260,  -260,  1160
};

/* YYDEFACT[STATE-NUM] -- Default reduction number in state STATE-NUM.
   Performed when YYTABLE does not specify something else to do.  Zero
   means the default is an error.  */
static const yytype_uint8 yydefact[] =
{
       0,     4,    21,    10,     5,     6,     7,     8,     0,    11,
      12,    13,     0,     0,     0,    14,     0,    23,    24,     0,
       0,     0,     0,   126,   126,     0,    88,    90,    91,     0,
      89,    92,    94,    95,    96,    97,    98,   103,     0,   101,
       0,   102,     0,     0,     0,    99,   100,   104,   105,   117,
     107,   108,   118,     2,   124,     3,     0,     0,   111,   112,
     113,   109,   165,   166,   167,   168,   169,   170,   110,   114,
     115,   116,    93,     0,   119,     0,   106,    22,   126,     9,
       0,   155,   153,   154,    28,   157,   156,    26,     0,     0,
      81,     0,   194,     0,    82,    75,   192,   127,    74,     0,
     127,   204,     1,     0,    50,     0,    52,    53,    35,    36,
      37,    38,    45,    51,    54,    56,    58,    16,    57,    59,
      42,    46,    25,   126,    62,    39,    47,    27,    63,    40,
      48,    35,     0,    31,    30,    36,    33,    37,    34,    43,
       0,    32,    44,    60,    61,    66,   126,    64,    65,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,   126,   122,     0,   150,
     151,     0,     0,     0,     0,     0,     0,     0,   152,    55,
     126,   206,   207,    68,    41,    49,    67,     0,    72,     0,
      29,   126,    17,    76,   128,   130,   131,   129,   132,   134,
     135,   136,   137,   138,   143,    77,   142,    78,   140,    80,
     146,    79,   149,     0,   133,   145,   147,   198,     0,    18,
     126,   126,    15,   120,   121,   189,     0,   188,     0,     0,
     177,   178,   179,   184,   185,   182,   183,   176,   187,   180,
     181,   186,   171,   172,   173,   174,   175,   125,   126,   158,
     159,   160,   161,   162,   164,   163,    84,    85,    86,    83,
     205,   126,    69,   126,     0,   126,   202,   199,     0,   200,
       0,    19,   193,   190,     0,    70,    87,   123,    73,     0,
      71,     0,     0,     0,   126,   191,   126,    71,   196,     0,
     203,   201,    20,     0,     0,   195,   208,   197
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int16 yypgoto[] =
{
    -260,  -260,    96,    99,   105,   148,   115,   119,   121,   122,
     123,   124,   128,  -260,   129,   173,     3,   174,    21,   179,
     139,  -260,    71,   134,   137,   141,   143,  -260,  -120,  -259,
    -260,   -21,   144,  -260,   145,  -260,     0,  -220,  -260,  -260,
    -260,     1,   146,  -260,  -260,  -260,  -260,  -260,  -260,  -260,
    -260,  -260,  -260,  -260,  -260,  -260,  -260,  -260,    56,  -260,
    -260,   147,  -260,  -260,  -260,  -260,  -260,    95,   181,   150
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_int16 yydefgoto[] =
{
       0,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      34,    35,    36,    93,    37,    38,    39,    40,    41,    42,
      43,    44,   111,    45,    46,    47,    48,    49,   187,    94,
      95,   188,    50,   259,    51,    52,   100,   225,    54,   248,
      55,    98,    57,   178,    58,    59,    60,    61,    62,    63,
      64,    65,    66,    67,    68,    69,    70,    71,   104,   105,
      99,    72,   217,   289,   268,   269,    73,    74,    75,    76
};

/* YYTABLE[YYPACT[STATE-NUM]] -- What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule whose
   number is the opposite.  If YYTABLE_NINF, syntax error.  */
static const yytype_int16 yytable[] =
{
      53,    56,    96,   228,   279,   131,   273,    77,   108,   132,
      79,   108,    81,    82,    83,   226,    77,    80,    84,    85,
      86,   227,   266,    97,    24,   101,   229,   293,   290,   127,
      17,    18,   109,    17,    18,    88,    17,    18,   182,   122,
      78,   109,   102,   109,   256,   109,   135,   109,   191,   265,
     110,   -21,    21,   -21,   285,    21,   267,    24,    21,   110,
      24,   110,   291,   110,   137,   110,   103,   166,   192,    17,
      18,   264,   123,    77,  -141,   103,   103,   146,   109,  -148,
     189,   103,   167,   106,   107,    16,   113,   114,   115,   116,
     117,    21,   118,   119,   205,   124,   110,   128,   218,   122,
     219,   143,   144,   224,   145,   127,   147,   148,   156,   120,
     182,   125,   206,   129,   139,   142,    87,   161,   162,   163,
     164,   165,   180,   103,   112,   261,   181,   274,   179,   262,
     183,   156,   186,   121,   156,   126,   261,   130,   140,   221,
     275,   222,   163,   164,   165,   281,   184,  -144,   177,   230,
     231,   232,   233,   234,   235,   236,   237,   238,   239,   240,
     241,   242,   243,   244,   245,   246,   282,   247,   249,   283,
     185,   250,   251,   252,   253,   254,   255,   286,  -141,   261,
     257,   260,   296,   276,   261,   261,   215,   194,   280,   287,
     195,   133,  -141,  -141,   122,  -139,   196,   103,   258,   -69,
     272,   -69,  -141,  -141,  -141,  -141,   197,  -141,  -141,   294,
     198,   295,   199,   200,   201,   202,   134,   136,   270,   203,
     204,   271,   138,   190,   141,   207,   224,   123,   208,  -141,
       0,   103,   209,     0,   210,   211,   212,   213,   214,     0,
     278,   216,     0,     0,     0,     0,     0,     0,     0,   277,
       0,   106,   107,   113,   114,   115,   116,   117,     0,   118,
     119,   124,   128,   143,   144,     0,   145,   147,   148,     0,
     179,   183,   186,     0,   224,     0,     0,     0,     0,     0,
       0,     0,   288,     0,     0,   292,     0,     0,     0,     0,
       0,     2,     3,     4,   297,     5,     6,     7,     8,     9,
      10,    11,     0,     0,    12,     0,     0,     0,    13,    14,
       0,    89,    15,     0,     0,    16,    17,    18,     0,     0,
       0,     0,     0,     0,     0,    90,     0,     0,     0,     0,
       0,    19,    20,     0,     0,     0,     0,     0,    21,    91,
       0,    23,     0,    24,     0,     0,     0,     1,    92,     2,
       3,     4,     0,     5,     6,     7,     8,     9,    10,    11,
       0,     0,    12,     0,     0,     0,    13,    14,     0,     0,
      15,     0,     0,    16,    17,    18,     0,     0,  -142,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,    19,
      20,     0,  -142,  -142,   127,  -148,    21,    22,  -126,    23,
       0,    24,  -142,  -142,  -142,  -142,     0,  -142,  -142,  -148,
    -148,     0,  -145,     0,     0,     0,     0,     0,     0,  -148,
    -148,  -148,  -148,     0,  -148,  -148,  -145,  -145,   182,  -142,
       0,   103,     0,     0,     0,     0,  -145,  -145,  -145,  -145,
       0,  -145,  -145,  -128,   146,     0,  -148,     0,   103,     0,
       0,     0,     0,     0,     0,     0,     0,  -128,  -128,     0,
    -130,     0,     0,  -145,     0,   103,     0,  -128,  -128,  -128,
    -128,     0,  -128,  -128,  -130,  -130,     0,  -131,     0,     0,
       0,     0,     0,     0,  -130,  -130,  -130,  -130,     0,  -130,
    -130,  -131,  -131,     0,  -128,  -129,   103,     0,     0,     0,
       0,  -131,  -131,  -131,  -131,     0,  -131,  -131,     0,  -129,
    -129,  -130,  -132,   103,     0,     0,     0,     0,     0,  -129,
    -129,  -129,  -129,     0,  -129,  -129,  -132,  -132,  -131,  -134,
     103,     0,     0,     0,     0,     0,  -132,  -132,  -132,  -132,
       0,  -132,  -132,  -134,  -134,     0,  -129,  -135,   103,     0,
       0,     0,     0,  -134,  -134,  -134,  -134,     0,  -134,  -134,
       0,  -135,  -135,  -132,  -136,   103,     0,     0,     0,     0,
       0,  -135,  -135,  -135,  -135,     0,  -135,  -135,  -136,  -136,
    -134,  -138,   103,     0,     0,     0,     0,     0,  -136,  -136,
    -136,  -136,     0,  -136,  -136,  -138,  -138,     0,  -135,  -143,
     103,     0,     0,     0,     0,  -138,  -138,  -138,  -138,     0,
    -138,  -138,     0,  -143,  -143,  -136,  -139,   103,     0,     0,
       0,     0,     0,  -143,  -143,  -143,  -143,     0,  -143,  -143,
    -139,  -139,  -138,  -140,   103,     0,     0,     0,     0,     0,
    -139,  -139,  -139,  -139,     0,  -139,  -139,  -140,  -140,     0,
    -143,  -146,   103,     0,     0,     0,     0,  -140,  -140,  -140,
    -140,     0,  -140,  -140,     0,  -146,  -146,  -139,  -149,   103,
       0,     0,     0,     0,     0,  -146,  -146,  -146,  -146,     0,
    -146,  -146,  -149,  -149,  -140,  -133,   103,     0,     0,     0,
       0,     0,  -149,  -149,  -149,  -149,     0,  -149,  -149,  -133,
    -133,     0,  -146,  -147,   103,     0,     0,     0,     0,  -133,
    -133,  -133,  -133,     0,  -133,  -133,     0,  -147,  -147,  -149,
       0,   103,     0,     0,     0,     0,     0,  -147,  -147,  -147,
    -147,     0,  -147,  -147,     0,     0,  -133,     0,   103,     0,
       2,     3,     4,     0,     5,     6,     7,     8,     9,    10,
      11,     0,     0,    12,  -147,     0,   103,    13,    14,     0,
       0,    15,     0,     0,    16,    17,    18,     0,     0,     0,
       0,     0,     0,     0,    90,     0,     0,     0,     0,     0,
      19,    20,     0,     0,     0,     0,     0,    21,    91,     0,
      23,     0,    24,     2,     3,     4,     0,     5,     6,     7,
       8,     9,    10,    11,     0,     0,    12,     0,     0,     0,
      13,    14,     0,     0,    15,     0,     0,    16,    17,    18,
       0,     0,     0,     0,     0,     0,     0,   223,     0,     0,
       0,     0,     0,    19,    20,     0,     0,     0,     0,     0,
      21,    22,     0,    23,     0,    24,     2,     3,     4,     0,
       5,     6,     7,     8,     9,    10,    11,     0,     0,    12,
     154,   155,     0,    13,    14,     0,     0,    15,     0,   156,
      16,    17,    18,     0,     0,   158,   159,   160,   161,   162,
     163,   164,   165,     0,     0,     0,    19,    20,     0,     0,
       0,     0,     0,    21,    22,     0,    23,     0,    24,     2,
       3,     4,     0,     5,     6,     7,     8,     9,    10,    11,
       0,     0,    12,     0,     0,     0,    13,    14,     0,     0,
      15,     0,     0,    16,    17,    18,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,    19,
      20,     0,     0,     0,     0,     0,    21,    91,     0,    23,
       0,    24,   193,     3,     4,     0,     5,     6,     7,     8,
       9,    10,    11,     0,     0,  -137,     0,     0,     0,     0,
       0,     0,     0,    15,     0,     0,    16,    17,    18,  -137,
    -137,     0,  -144,     0,     0,     0,     0,     0,     0,  -137,
    -137,  -137,  -137,     0,  -137,  -137,  -144,  -144,     0,    21,
     168,     0,    23,     0,    24,     0,  -144,  -144,  -144,  -144,
       0,  -144,  -144,     0,   169,   170,  -137,     0,     0,     0,
       0,     0,     0,     0,   171,   172,   173,   174,     0,   175,
     176,     0,     0,  -144,   149,   150,     0,   151,   152,   153,
       0,     0,     0,     0,     0,   154,   155,     0,     0,     0,
       0,   177,     0,     0,   156,     0,     0,     0,     0,   157,
     158,   159,   160,   161,   162,   163,   164,   165,     0,     0,
     149,   150,  -127,   151,   152,   153,     0,     0,     0,     0,
       0,   154,   155,     0,     0,     0,     0,     0,     0,     0,
     156,     0,     0,     0,     0,   157,   158,   159,   160,   161,
     162,   163,   164,   165,     0,     0,   149,   150,   263,   151,
     152,   153,     0,     0,     0,   220,     0,   154,   155,     0,
       0,     0,     0,     0,     0,     0,   156,     0,     0,     0,
       0,   157,   158,   159,   160,   161,   162,   163,   164,   165,
     149,   150,     0,   151,   152,   153,     0,     0,     0,   284,
       0,   154,   155,     0,     0,     0,     0,     0,     0,     0,
     156,     0,     0,     0,     0,   157,   158,   159,   160,   161,
     162,   163,   164,   165,   149,   150,     0,   151,   152,   153,
       0,     0,     0,     0,     0,   154,   155,     0,     0,     0,
       0,     0,     0,     0,   156,     0,     0,     0,     0,   157,
     158,   159,   160,   161,   162,   163,   164,   165,   149,     0,
       0,   151,   152,   153,     0,     0,     0,     0,     0,   154,
     155,     0,     0,     0,     0,     0,     0,     0,   156,     0,
       0,     0,     0,   157,   158,   159,   160,   161,   162,   163,
     164,   165,   151,   152,   153,     0,     0,     0,     0,     0,
     154,   155,     0,     0,     0,     0,     0,     0,     0,   156,
       0,     0,     0,     0,   157,   158,   159,   160,   161,   162,
     163,   164,   165
};

static const yytype_int16 yycheck[] =
{
       0,     0,    23,   123,   263,     3,   226,    22,     3,     7,
      22,     3,    12,    13,    14,    52,    22,    55,    22,    19,
      20,    58,     3,    23,    55,    24,   146,   286,     3,    22,
      28,    29,    29,    28,    29,     3,    28,    29,    22,    22,
      55,    38,     0,    40,     3,    42,    43,    44,    55,    55,
      29,    57,    50,    59,   274,    50,    37,    55,    50,    38,
      55,    40,    37,    42,    43,    44,    59,    52,    54,    28,
      29,   191,    55,    22,    57,    59,    59,    55,    75,    57,
      80,    59,    52,    27,    28,    27,    30,    31,    32,    33,
      34,    50,    36,    37,    91,    39,    75,    41,    52,    22,
      54,    45,    46,   103,    48,    22,    50,    51,    34,    38,
      22,    40,    91,    42,    43,    44,    21,    43,    44,    45,
      46,    47,    52,    59,    29,    52,    56,    59,    72,    56,
      74,    34,    76,    38,    34,    40,    52,    42,    43,    52,
      56,    54,    45,    46,    47,   265,    75,    57,    57,   149,
     150,   151,   152,   153,   154,   155,   156,   157,   158,   159,
     160,   161,   162,   163,   164,   165,    60,   166,   168,    52,
      75,   171,   172,   173,   174,   175,   176,    52,     6,    52,
     177,   180,    56,    56,    52,    52,    91,    91,    56,    56,
      91,    43,    20,    21,    22,    57,    91,    59,   177,    57,
     221,    59,    30,    31,    32,    33,    91,    35,    36,    52,
      91,    54,    91,    91,    91,    91,    43,    43,   218,    91,
      91,   220,    43,    84,    43,    91,   226,    55,    91,    57,
      -1,    59,    91,    -1,    91,    91,    91,    91,    91,    -1,
     261,    91,    -1,    -1,    -1,    -1,    -1,    -1,    -1,   248,
      -1,   195,   196,   197,   198,   199,   200,   201,    -1,   203,
     204,   205,   206,   207,   208,    -1,   210,   211,   212,    -1,
     214,   215,   216,    -1,   274,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,   282,    -1,    -1,   284,    -1,    -1,    -1,    -1,
      -1,     3,     4,     5,   294,     7,     8,     9,    10,    11,
      12,    13,    -1,    -1,    16,    -1,    -1,    -1,    20,    21,
      -1,    23,    24,    -1,    -1,    27,    28,    29,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    37,    -1,    -1,    -1,    -1,
      -1,    43,    44,    -1,    -1,    -1,    -1,    -1,    50,    51,
      -1,    53,    -1,    55,    -1,    -1,    -1,     1,    60,     3,
       4,     5,    -1,     7,     8,     9,    10,    11,    12,    13,
      -1,    -1,    16,    -1,    -1,    -1,    20,    21,    -1,    -1,
      24,    -1,    -1,    27,    28,    29,    -1,    -1,     6,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      44,    -1,    20,    21,    22,     6,    50,    51,    52,    53,
      -1,    55,    30,    31,    32,    33,    -1,    35,    36,    20,
      21,    -1,     6,    -1,    -1,    -1,    -1,    -1,    -1,    30,
      31,    32,    33,    -1,    35,    36,    20,    21,    22,    57,
      -1,    59,    -1,    -1,    -1,    -1,    30,    31,    32,    33,
      -1,    35,    36,     6,    55,    -1,    57,    -1,    59,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    20,    21,    -1,
       6,    -1,    -1,    57,    -1,    59,    -1,    30,    31,    32,
      33,    -1,    35,    36,    20,    21,    -1,     6,    -1,    -1,
      -1,    -1,    -1,    -1,    30,    31,    32,    33,    -1,    35,
      36,    20,    21,    -1,    57,     6,    59,    -1,    -1,    -1,
      -1,    30,    31,    32,    33,    -1,    35,    36,    -1,    20,
      21,    57,     6,    59,    -1,    -1,    -1,    -1,    -1,    30,
      31,    32,    33,    -1,    35,    36,    20,    21,    57,     6,
      59,    -1,    -1,    -1,    -1,    -1,    30,    31,    32,    33,
      -1,    35,    36,    20,    21,    -1,    57,     6,    59,    -1,
      -1,    -1,    -1,    30,    31,    32,    33,    -1,    35,    36,
      -1,    20,    21,    57,     6,    59,    -1,    -1,    -1,    -1,
      -1,    30,    31,    32,    33,    -1,    35,    36,    20,    21,
      57,     6,    59,    -1,    -1,    -1,    -1,    -1,    30,    31,
      32,    33,    -1,    35,    36,    20,    21,    -1,    57,     6,
      59,    -1,    -1,    -1,    -1,    30,    31,    32,    33,    -1,
      35,    36,    -1,    20,    21,    57,     6,    59,    -1,    -1,
      -1,    -1,    -1,    30,    31,    32,    33,    -1,    35,    36,
      20,    21,    57,     6,    59,    -1,    -1,    -1,    -1,    -1,
      30,    31,    32,    33,    -1,    35,    36,    20,    21,    -1,
      57,     6,    59,    -1,    -1,    -1,    -1,    30,    31,    32,
      33,    -1,    35,    36,    -1,    20,    21,    57,     6,    59,
      -1,    -1,    -1,    -1,    -1,    30,    31,    32,    33,    -1,
      35,    36,    20,    21,    57,     6,    59,    -1,    -1,    -1,
      -1,    -1,    30,    31,    32,    33,    -1,    35,    36,    20,
      21,    -1,    57,     6,    59,    -1,    -1,    -1,    -1,    30,
      31,    32,    33,    -1,    35,    36,    -1,    20,    21,    57,
      -1,    59,    -1,    -1,    -1,    -1,    -1,    30,    31,    32,
      33,    -1,    35,    36,    -1,    -1,    57,    -1,    59,    -1,
       3,     4,     5,    -1,     7,     8,     9,    10,    11,    12,
      13,    -1,    -1,    16,    57,    -1,    59,    20,    21,    -1,
      -1,    24,    -1,    -1,    27,    28,    29,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    37,    -1,    -1,    -1,    -1,    -1,
      43,    44,    -1,    -1,    -1,    -1,    -1,    50,    51,    -1,
      53,    -1,    55,     3,     4,     5,    -1,     7,     8,     9,
      10,    11,    12,    13,    -1,    -1,    16,    -1,    -1,    -1,
      20,    21,    -1,    -1,    24,    -1,    -1,    27,    28,    29,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    37,    -1,    -1,
      -1,    -1,    -1,    43,    44,    -1,    -1,    -1,    -1,    -1,
      50,    51,    -1,    53,    -1,    55,     3,     4,     5,    -1,
       7,     8,     9,    10,    11,    12,    13,    -1,    -1,    16,
      25,    26,    -1,    20,    21,    -1,    -1,    24,    -1,    34,
      27,    28,    29,    -1,    -1,    40,    41,    42,    43,    44,
      45,    46,    47,    -1,    -1,    -1,    43,    44,    -1,    -1,
      -1,    -1,    -1,    50,    51,    -1,    53,    -1,    55,     3,
       4,     5,    -1,     7,     8,     9,    10,    11,    12,    13,
      -1,    -1,    16,    -1,    -1,    -1,    20,    21,    -1,    -1,
      24,    -1,    -1,    27,    28,    29,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      44,    -1,    -1,    -1,    -1,    -1,    50,    51,    -1,    53,
      -1,    55,     3,     4,     5,    -1,     7,     8,     9,    10,
      11,    12,    13,    -1,    -1,     6,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    24,    -1,    -1,    27,    28,    29,    20,
      21,    -1,     6,    -1,    -1,    -1,    -1,    -1,    -1,    30,
      31,    32,    33,    -1,    35,    36,    20,    21,    -1,    50,
       6,    -1,    53,    -1,    55,    -1,    30,    31,    32,    33,
      -1,    35,    36,    -1,    20,    21,    57,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    30,    31,    32,    33,    -1,    35,
      36,    -1,    -1,    57,    14,    15,    -1,    17,    18,    19,
      -1,    -1,    -1,    -1,    -1,    25,    26,    -1,    -1,    -1,
      -1,    57,    -1,    -1,    34,    -1,    -1,    -1,    -1,    39,
      40,    41,    42,    43,    44,    45,    46,    47,    -1,    -1,
      14,    15,    52,    17,    18,    19,    -1,    -1,    -1,    -1,
      -1,    25,    26,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      34,    -1,    -1,    -1,    -1,    39,    40,    41,    42,    43,
      44,    45,    46,    47,    -1,    -1,    14,    15,    52,    17,
      18,    19,    -1,    -1,    -1,    23,    -1,    25,    26,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    34,    -1,    -1,    -1,
      -1,    39,    40,    41,    42,    43,    44,    45,    46,    47,
      14,    15,    -1,    17,    18,    19,    -1,    -1,    -1,    23,
      -1,    25,    26,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      34,    -1,    -1,    -1,    -1,    39,    40,    41,    42,    43,
      44,    45,    46,    47,    14,    15,    -1,    17,    18,    19,
      -1,    -1,    -1,    -1,    -1,    25,    26,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    34,    -1,    -1,    -1,    -1,    39,
      40,    41,    42,    43,    44,    45,    46,    47,    14,    -1,
      -1,    17,    18,    19,    -1,    -1,    -1,    -1,    -1,    25,
      26,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    34,    -1,
      -1,    -1,    -1,    39,    40,    41,    42,    43,    44,    45,
      46,    47,    17,    18,    19,    -1,    -1,    -1,    -1,    -1,
      25,    26,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    34,
      -1,    -1,    -1,    -1,    39,    40,    41,    42,    43,    44,
      45,    46,    47
};

/* YYSTOS[STATE-NUM] -- The symbol kind of the accessing symbol of
   state STATE-NUM.  */
static const yytype_uint8 yystos[] =
{
       0,     1,     3,     4,     5,     7,     8,     9,    10,    11,
      12,    13,    16,    20,    21,    24,    27,    28,    29,    43,
      44,    50,    51,    53,    55,    62,    63,    64,    65,    66,
      67,    68,    69,    70,    71,    72,    73,    75,    76,    77,
      78,    79,    80,    81,    82,    84,    85,    86,    87,    88,
      93,    95,    96,    97,    99,   101,   102,   103,   105,   106,
     107,   108,   109,   110,   111,   112,   113,   114,   115,   116,
     117,   118,   122,   127,   128,   129,   130,    22,    55,    22,
      55,    97,    97,    97,    22,    97,    97,   128,     3,    23,
      37,    51,    60,    74,    90,    91,    92,    97,   102,   121,
      97,   102,     0,    59,   119,   120,   119,   119,     3,    77,
      79,    83,   128,   119,   119,   119,   119,   119,   119,   119,
      83,   128,    22,    55,   119,    83,   128,    22,   119,    83,
     128,     3,     7,    66,    76,    77,    78,    79,    80,    83,
     128,   129,    83,   119,   119,   119,    55,   119,   119,    14,
      15,    17,    18,    19,    25,    26,    34,    39,    40,    41,
      42,    43,    44,    45,    46,    47,    52,    52,     6,    20,
      21,    30,    31,    32,    33,    35,    36,    57,   104,   119,
      52,    56,    22,   119,    83,   128,   119,    89,    92,    97,
      81,    55,    54,     3,    63,    64,    65,    67,    68,    69,
      70,    71,    72,    73,    75,    77,    79,    84,    85,    86,
      87,    93,    95,   103,   122,   128,   130,   123,    52,    54,
      23,    52,    54,    37,    97,    98,    52,    58,    89,    89,
      97,    97,    97,    97,    97,    97,    97,    97,    97,    97,
      97,    97,    97,    97,    97,    97,    97,   102,   100,    97,
      97,    97,    97,    97,    97,    97,     3,    77,    79,    94,
     102,    52,    56,    52,    89,    55,     3,    37,   125,   126,
      97,   102,    92,    98,    59,    56,    56,   102,    92,    90,
      56,    89,    60,    52,    23,    98,    52,    56,    97,   124,
       3,    37,   102,    90,    52,    54,    56,    97
};

/* YYR1[RULE-NUM] -- Symbol kind of the left-hand side of rule RULE-NUM.  */
static const yytype_uint8 yyr1[] =
{
       0,    61,    62,    62,    62,    63,    63,    64,    65,    66,
      67,    68,    69,    69,    70,    71,    72,    73,    73,    74,
      74,    75,    76,    77,    77,    78,    79,    80,    81,    81,
      82,    82,    82,    82,    82,    83,    83,    83,    84,    84,
      84,    84,    84,    84,    84,    85,    85,    85,    85,    85,
      86,    86,    86,    86,    86,    86,    86,    86,    86,    86,
      86,    86,    86,    86,    86,    86,    86,    86,    86,    87,
      87,    88,    89,    89,    90,    90,    91,    91,    91,    91,
      91,    92,    92,    93,    94,    94,    94,    95,    96,    96,
      96,    96,    96,    96,    96,    96,    96,    96,    96,    96,
      96,    96,    96,    96,    96,    96,    96,    96,    96,    96,
      96,    96,    96,    96,    96,    96,    96,    96,    97,    97,
      98,    98,   100,    99,   101,   101,   102,   102,   103,   103,
     103,   103,   103,   103,   103,   103,   103,   103,   103,   103,
     103,   103,   103,   103,   103,   103,   103,   103,   103,   103,
     104,   104,   105,   106,   106,   107,   107,   107,   108,   109,
     110,   111,   112,   113,   114,   115,   115,   115,   115,   115,
     115,   116,   116,   116,   116,   116,   116,   117,   117,   118,
     118,   118,   118,   118,   118,   118,   118,   118,   119,   120,
     120,   120,   121,   121,   123,   122,   124,   124,   125,   125,
     125,   125,   126,   126,   127,   127,   128,   129,   130
};

/* YYR2[RULE-NUM] -- Number of symbols on the right-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr2[] =
{
       0,     2,     1,     1,     1,     1,     1,     1,     1,     2,
       1,     1,     1,     1,     1,     3,     2,     3,     3,     3,
       5,     1,     2,     1,     1,     2,     2,     2,     2,     3,
       2,     2,     2,     2,     2,     1,     1,     1,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     4,
       4,     5,     1,     3,     1,     1,     2,     2,     2,     2,
       2,     1,     1,     3,     1,     1,     1,     4,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1,
       1,     1,     0,     4,     1,     3,     0,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1,
       1,     1,     2,     2,     2,     2,     2,     2,     3,     3,
       3,     3,     3,     3,     3,     1,     1,     1,     1,     1,
       1,     3,     3,     3,     3,     3,     3,     3,     3,     3,
       3,     3,     3,     3,     3,     3,     3,     3,     2,     2,
       3,     4,     1,     3,     0,     7,     1,     3,     0,     1,
       1,     3,     1,     3,     2,     3,     2,     2,     8
};


enum { YYENOMEM = -2 };

#define yyerrok         (yyerrstatus = 0)
#define yyclearin       (yychar = HB_MACRO_YYEMPTY)

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYNOMEM         goto yyexhaustedlab


#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)                                    \
  do                                                              \
    if (yychar == HB_MACRO_YYEMPTY)                                        \
      {                                                           \
        yychar = (Token);                                         \
        yylval = (Value);                                         \
        YYPOPSTACK (yylen);                                       \
        yystate = *yyssp;                                         \
        goto yybackup;                                            \
      }                                                           \
    else                                                          \
      {                                                           \
        yyerror (pMacro, YY_("syntax error: cannot back up")); \
        YYERROR;                                                  \
      }                                                           \
  while (0)

/* Backward compatibility with an undocumented macro.
   Use HB_MACRO_YYerror or HB_MACRO_YYUNDEF. */
#define YYERRCODE HB_MACRO_YYUNDEF


/* Enable debugging if requested.  */
#if HB_MACRO_YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)                        \
do {                                            \
  if (yydebug)                                  \
    YYFPRINTF Args;                             \
} while (0)




# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)                    \
do {                                                                      \
  if (yydebug)                                                            \
    {                                                                     \
      YYFPRINTF (stderr, "%s ", Title);                                   \
      yy_symbol_print (stderr,                                            \
                  Kind, Value, pMacro); \
      YYFPRINTF (stderr, "\n");                                           \
    }                                                                     \
} while (0)


/*-----------------------------------.
| Print this symbol's value on YYO.  |
`-----------------------------------*/

static void
yy_symbol_value_print (FILE *yyo,
                       yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep, PHB_MACRO pMacro)
{
  FILE *yyoutput = yyo;
  YY_USE (yyoutput);
  YY_USE (pMacro);
  if (!yyvaluep)
    return;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/*---------------------------.
| Print this symbol on YYO.  |
`---------------------------*/

static void
yy_symbol_print (FILE *yyo,
                 yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep, PHB_MACRO pMacro)
{
  YYFPRINTF (yyo, "%s %s (",
             yykind < YYNTOKENS ? "token" : "nterm", yysymbol_name (yykind));

  yy_symbol_value_print (yyo, yykind, yyvaluep, pMacro);
  YYFPRINTF (yyo, ")");
}

/*------------------------------------------------------------------.
| yy_stack_print -- Print the state stack from its BOTTOM up to its |
| TOP (included).                                                   |
`------------------------------------------------------------------*/

static void
yy_stack_print (yy_state_t *yybottom, yy_state_t *yytop)
{
  YYFPRINTF (stderr, "Stack now");
  for (; yybottom <= yytop; yybottom++)
    {
      int yybot = *yybottom;
      YYFPRINTF (stderr, " %d", yybot);
    }
  YYFPRINTF (stderr, "\n");
}

# define YY_STACK_PRINT(Bottom, Top)                            \
do {                                                            \
  if (yydebug)                                                  \
    yy_stack_print ((Bottom), (Top));                           \
} while (0)


/*------------------------------------------------.
| Report that the YYRULE is going to be reduced.  |
`------------------------------------------------*/

static void
yy_reduce_print (yy_state_t *yyssp, YYSTYPE *yyvsp,
                 int yyrule, PHB_MACRO pMacro)
{
  int yylno = yyrline[yyrule];
  int yynrhs = yyr2[yyrule];
  int yyi;
  YYFPRINTF (stderr, "Reducing stack by rule %d (line %d):\n",
             yyrule - 1, yylno);
  /* The symbols being reduced.  */
  for (yyi = 0; yyi < yynrhs; yyi++)
    {
      YYFPRINTF (stderr, "   $%d = ", yyi + 1);
      yy_symbol_print (stderr,
                       YY_ACCESSING_SYMBOL (+yyssp[yyi + 1 - yynrhs]),
                       &yyvsp[(yyi + 1) - (yynrhs)], pMacro);
      YYFPRINTF (stderr, "\n");
    }
}

# define YY_REDUCE_PRINT(Rule)          \
do {                                    \
  if (yydebug)                          \
    yy_reduce_print (yyssp, yyvsp, Rule, pMacro); \
} while (0)

/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !HB_MACRO_YYDEBUG */
# define YYDPRINTF(Args) ((void) 0)
# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)
# define YY_STACK_PRINT(Bottom, Top)
# define YY_REDUCE_PRINT(Rule)
#endif /* !HB_MACRO_YYDEBUG */


/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef YYINITDEPTH
# define YYINITDEPTH 200
#endif

/* YYMAXDEPTH -- maximum size the stacks can grow to (effective only
   if the built-in stack extension method is used).

   Do not make this value too large; the results are undefined if
   YYSTACK_ALLOC_MAXIMUM < YYSTACK_BYTES (YYMAXDEPTH)
   evaluated with infinite-precision integer arithmetic.  */

#ifndef YYMAXDEPTH
# define YYMAXDEPTH 10000
#endif






/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

static void
yydestruct (const char *yymsg,
            yysymbol_kind_t yykind, YYSTYPE *yyvaluep, PHB_MACRO pMacro)
{
  YY_USE (yyvaluep);
  YY_USE (pMacro);
  if (!yymsg)
    yymsg = "Deleting";
  YY_SYMBOL_PRINT (yymsg, yykind, yyvaluep, yylocationp);

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}






/*----------.
| yyparse.  |
`----------*/

int
yyparse (PHB_MACRO pMacro)
{
/* Lookahead token kind.  */
int yychar;


/* The semantic value of the lookahead symbol.  */
/* Default value used for initialization, for pacifying older GCCs
   or non-GCC compilers.  */
YY_INITIAL_VALUE (static YYSTYPE yyval_default;)
YYSTYPE yylval YY_INITIAL_VALUE (= yyval_default);

    /* Number of syntax errors so far.  */
    int yynerrs = 0;

    yy_state_fast_t yystate = 0;
    /* Number of tokens to shift before error messages enabled.  */
    int yyerrstatus = 0;

    /* Refer to the stacks through separate pointers, to allow yyoverflow
       to reallocate them elsewhere.  */

    /* Their size.  */
    YYPTRDIFF_T yystacksize = YYINITDEPTH;

    /* The state stack: array, bottom, top.  */
    yy_state_t yyssa[YYINITDEPTH];
    yy_state_t *yyss = yyssa;
    yy_state_t *yyssp = yyss;

    /* The semantic value stack: array, bottom, top.  */
    YYSTYPE yyvsa[YYINITDEPTH];
    YYSTYPE *yyvs = yyvsa;
    YYSTYPE *yyvsp = yyvs;

  int yyn;
  /* The return value of yyparse.  */
  int yyresult;
  /* Lookahead symbol kind.  */
  yysymbol_kind_t yytoken = YYSYMBOL_YYEMPTY;
  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;



#define YYPOPSTACK(N)   (yyvsp -= (N), yyssp -= (N))

  /* The number of symbols on the RHS of the reduced rule.
     Keep to zero when no symbol should be popped.  */
  int yylen = 0;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yychar = HB_MACRO_YYEMPTY; /* Cause a token to be read.  */

  goto yysetstate;


/*------------------------------------------------------------.
| yynewstate -- push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed.  So pushing a state here evens the stacks.  */
  yyssp++;


/*--------------------------------------------------------------------.
| yysetstate -- set current state (the top of the stack) to yystate.  |
`--------------------------------------------------------------------*/
yysetstate:
  YYDPRINTF ((stderr, "Entering state %d\n", yystate));
  YY_ASSERT (0 <= yystate && yystate < YYNSTATES);
  YY_IGNORE_USELESS_CAST_BEGIN
  *yyssp = YY_CAST (yy_state_t, yystate);
  YY_IGNORE_USELESS_CAST_END
  YY_STACK_PRINT (yyss, yyssp);

  if (yyss + yystacksize - 1 <= yyssp)
#if !defined yyoverflow && !defined YYSTACK_RELOCATE
    YYNOMEM;
#else
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYPTRDIFF_T yysize = yyssp - yyss + 1;

# if defined yyoverflow
      {
        /* Give user a chance to reallocate the stack.  Use copies of
           these so that the &'s don't force the real ones into
           memory.  */
        yy_state_t *yyss1 = yyss;
        YYSTYPE *yyvs1 = yyvs;

        /* Each stack pointer address is followed by the size of the
           data in use in that stack, in bytes.  This used to be a
           conditional around just the two extra args, but that might
           be undefined if yyoverflow is a macro.  */
        yyoverflow (YY_("memory exhausted"),
                    &yyss1, yysize * YYSIZEOF (*yyssp),
                    &yyvs1, yysize * YYSIZEOF (*yyvsp),
                    &yystacksize);
        yyss = yyss1;
        yyvs = yyvs1;
      }
# else /* defined YYSTACK_RELOCATE */
      /* Extend the stack our own way.  */
      if (YYMAXDEPTH <= yystacksize)
        YYNOMEM;
      yystacksize *= 2;
      if (YYMAXDEPTH < yystacksize)
        yystacksize = YYMAXDEPTH;

      {
        yy_state_t *yyss1 = yyss;
        union yyalloc *yyptr =
          YY_CAST (union yyalloc *,
                   YYSTACK_ALLOC (YY_CAST (YYSIZE_T, YYSTACK_BYTES (yystacksize))));
        if (! yyptr)
          YYNOMEM;
        YYSTACK_RELOCATE (yyss_alloc, yyss);
        YYSTACK_RELOCATE (yyvs_alloc, yyvs);
#  undef YYSTACK_RELOCATE
        if (yyss1 != yyssa)
          YYSTACK_FREE (yyss1);
      }
# endif

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;

      YY_IGNORE_USELESS_CAST_BEGIN
      YYDPRINTF ((stderr, "Stack size increased to %ld\n",
                  YY_CAST (long, yystacksize)));
      YY_IGNORE_USELESS_CAST_END

      if (yyss + yystacksize - 1 <= yyssp)
        YYABORT;
    }
#endif /* !defined yyoverflow && !defined YYSTACK_RELOCATE */


  if (yystate == YYFINAL)
    YYACCEPT;

  goto yybackup;


/*-----------.
| yybackup.  |
`-----------*/
yybackup:
  /* Do appropriate processing given the current state.  Read a
     lookahead token if we need one and don't already have one.  */

  /* First try to decide what to do without reference to lookahead token.  */
  yyn = yypact[yystate];
  if (yypact_value_is_default (yyn))
    goto yydefault;

  /* Not known => get a lookahead token if don't already have one.  */

  /* YYCHAR is either empty, or end-of-input, or a valid lookahead.  */
  if (yychar == HB_MACRO_YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token\n"));
      yychar = yylex (&yylval, pMacro);
    }

  if (yychar <= HB_MACRO_YYEOF)
    {
      yychar = HB_MACRO_YYEOF;
      yytoken = YYSYMBOL_YYEOF;
      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else if (yychar == HB_MACRO_YYerror)
    {
      /* The scanner already issued an error message, process directly
         to error recovery.  But do not keep the error token as
         lookahead, it is too special and may lead us to an endless
         loop in error recovery. */
      yychar = HB_MACRO_YYUNDEF;
      yytoken = YYSYMBOL_YYerror;
      goto yyerrlab1;
    }
  else
    {
      yytoken = YYTRANSLATE (yychar);
      YY_SYMBOL_PRINT ("Next token is", yytoken, &yylval, &yylloc);
    }

  /* If the proper action on seeing token YYTOKEN is to reduce or to
     detect an error, take that action.  */
  yyn += yytoken;
  if (yyn < 0 || YYLAST < yyn || yycheck[yyn] != yytoken)
    goto yydefault;
  yyn = yytable[yyn];
  if (yyn <= 0)
    {
      if (yytable_value_is_error (yyn))
        goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  /* Shift the lookahead token.  */
  YY_SYMBOL_PRINT ("Shifting", yytoken, &yylval, &yylloc);
  yystate = yyn;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END

  /* Discard the shifted token.  */
  yychar = HB_MACRO_YYEMPTY;
  goto yynewstate;


/*-----------------------------------------------------------.
| yydefault -- do the default action for the current state.  |
`-----------------------------------------------------------*/
yydefault:
  yyn = yydefact[yystate];
  if (yyn == 0)
    goto yyerrlab;
  goto yyreduce;


/*-----------------------------.
| yyreduce -- do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     '$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];


  YY_REDUCE_PRINT (yyn);
  switch (yyn)
    {
  case 2: /* Main: Expression  */
#line 257 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                        {
                           HB_MACRO_DATA->exprType = hb_compExprType( (yyvsp[0].asExpr) );
                           if( HB_MACRO_DATA->Flags &  HB_MACRO_GEN_REFER )
                              hb_macroExprGenPush( hb_compExprNewRef( (yyvsp[0].asExpr), HB_COMP_PARAM ), HB_COMP_PARAM );
                           else if( HB_MACRO_DATA->Flags &  HB_MACRO_GEN_PUSH )
                              hb_macroExprGenPush( (yyvsp[0].asExpr), HB_COMP_PARAM );
                           else
                              hb_macroExprGenPop( (yyvsp[0].asExpr), HB_COMP_PARAM );
                           hb_macroGenPCode1( HB_P_ENDPROC, HB_COMP_PARAM );
                        }
#line 1779 "macroy.c"
    break;

  case 3: /* Main: AsParamList  */
#line 267 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                        {
                           HB_MACRO_DATA->exprType = hb_compExprType( (yyvsp[0].asExpr) );
                           if( HB_MACRO_DATA->Flags &  HB_MACRO_GEN_PUSH )
                              hb_macroExprGenPush( (yyvsp[0].asExpr), HB_COMP_PARAM );
                           else
                              hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
                           hb_macroGenPCode1( HB_P_ENDPROC, HB_COMP_PARAM );
                        }
#line 1792 "macroy.c"
    break;

  case 4: /* Main: error  */
#line 275 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
               {
                  HB_TRACE( HB_TR_DEBUG, ( "macro -> invalid syntax: %s", HB_MACRO_DATA->string ) );
                  hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
                  HB_MACRO_ABORT;
               }
#line 1802 "macroy.c"
    break;

  case 5: /* NumValue: NUM_DOUBLE  */
#line 284 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewDouble( (yyvsp[0].valDouble).dNumber, (yyvsp[0].valDouble).bWidth, (yyvsp[0].valDouble).bDec, HB_COMP_PARAM ); }
#line 1808 "macroy.c"
    break;

  case 6: /* NumValue: NUM_LONG  */
#line 285 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewLong( (yyvsp[0].valLong).lNumber, HB_COMP_PARAM ); }
#line 1814 "macroy.c"
    break;

  case 7: /* DateValue: NUM_DATE  */
#line 288 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewDate( ( long ) (yyvsp[0].valLong).lNumber, HB_COMP_PARAM ); }
#line 1820 "macroy.c"
    break;

  case 8: /* TimeStampValue: TIMESTAMP  */
#line 291 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewTimeStamp( (yyvsp[0].valTimeStamp).date, (yyvsp[0].valTimeStamp).time, HB_COMP_PARAM ); }
#line 1826 "macroy.c"
    break;

  case 9: /* NumAlias: NUM_LONG ALIASOP  */
#line 294 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewLong( (yyvsp[-1].valLong).lNumber, HB_COMP_PARAM ); }
#line 1832 "macroy.c"
    break;

  case 10: /* NilValue: NIL  */
#line 299 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewNil( HB_COMP_PARAM ); }
#line 1838 "macroy.c"
    break;

  case 11: /* LiteralValue: LITERAL  */
#line 304 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewString( (yyvsp[0].valChar).string, (yyvsp[0].valChar).length, HB_FALSE, HB_COMP_PARAM ); }
#line 1844 "macroy.c"
    break;

  case 12: /* Logical: TRUEVALUE  */
#line 309 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewLogical( HB_TRUE, HB_COMP_PARAM ); }
#line 1850 "macroy.c"
    break;

  case 13: /* Logical: FALSEVALUE  */
#line 310 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewLogical( HB_FALSE, HB_COMP_PARAM ); }
#line 1856 "macroy.c"
    break;

  case 14: /* SelfValue: SELF  */
#line 315 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewSelf( HB_COMP_PARAM ); }
#line 1862 "macroy.c"
    break;

  case 15: /* Array: '{' ElemList '}'  */
#line 320 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewArray( (yyvsp[-1].asExpr), HB_COMP_PARAM ); }
#line 1868 "macroy.c"
    break;

  case 16: /* ArrayAt: Array ArrayIndex  */
#line 325 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1874 "macroy.c"
    break;

  case 17: /* Hash: '{' HASHOP '}'  */
#line 330 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewHash( NULL, HB_COMP_PARAM ); }
#line 1880 "macroy.c"
    break;

  case 18: /* Hash: '{' HashList '}'  */
#line 331 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewHash( (yyvsp[-1].asExpr), HB_COMP_PARAM ); }
#line 1886 "macroy.c"
    break;

  case 19: /* HashList: Expression HASHOP EmptyExpression  */
#line 334 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                               { (yyval.asExpr) = hb_compExprAddListExpr( hb_compExprNewList( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr) ); }
#line 1892 "macroy.c"
    break;

  case 20: /* HashList: HashList ',' Expression HASHOP EmptyExpression  */
#line 335 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                               { (yyval.asExpr) = hb_compExprAddListExpr( hb_compExprAddListExpr( (yyvsp[-4].asExpr), (yyvsp[-2].asExpr) ), (yyvsp[0].asExpr) ); }
#line 1898 "macroy.c"
    break;

  case 21: /* Variable: IDENTIFIER  */
#line 341 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewVar( (yyvsp[0].string), HB_COMP_PARAM ); }
#line 1904 "macroy.c"
    break;

  case 22: /* VarAlias: IDENTIFIER ALIASOP  */
#line 344 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewAlias( (yyvsp[-1].string), HB_COMP_PARAM ); }
#line 1910 "macroy.c"
    break;

  case 23: /* MacroVar: MACROVAR  */
#line 349 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              {  (yyval.asExpr) = hb_compExprNewMacro( NULL, '&', (yyvsp[0].string), HB_COMP_PARAM );
                                 HB_MACRO_CHECK( (yyval.asExpr) );
                              }
#line 1918 "macroy.c"
    break;

  case 24: /* MacroVar: MACROTEXT  */
#line 352 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              {  HB_BOOL fNewString;
                                 char * szVarName = hb_macroTextSymbol( (yyvsp[0].string), strlen( (yyvsp[0].string) ), &fNewString );
                                 if( szVarName )
                                 {
                                    if( fNewString )
                                       hb_macroIdentNew( HB_COMP_PARAM, szVarName );
                                    (yyval.asExpr) = hb_compExprNewVar( szVarName, HB_COMP_PARAM );
                                    HB_MACRO_CHECK( (yyval.asExpr) );
                                 }
                                 else
                                 {
                                    /* invalid variable name
                                     */
                                    HB_TRACE( HB_TR_DEBUG, ( "macro -> invalid variable name: %s", (yyvsp[0].string) ) );
                                    YYABORT;
                                 }
                              }
#line 1940 "macroy.c"
    break;

  case 25: /* MacroVarAlias: MacroVar ALIASOP  */
#line 371 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { hb_compExprMacroAsAlias( (yyvsp[-1].asExpr) ); }
#line 1946 "macroy.c"
    break;

  case 26: /* MacroExpr: '&' PareExpList  */
#line 376 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewMacro( (yyvsp[0].asExpr), 0, NULL, HB_COMP_PARAM ); }
#line 1952 "macroy.c"
    break;

  case 28: /* FieldAlias: FIELD ALIASOP  */
#line 386 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAlias( "FIELD", HB_COMP_PARAM ); }
#line 1958 "macroy.c"
    break;

  case 29: /* FieldAlias: FIELD ALIASOP FieldAlias  */
#line 387 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1964 "macroy.c"
    break;

  case 30: /* FieldVarAlias: FieldAlias VarAlias  */
#line 392 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1970 "macroy.c"
    break;

  case 31: /* FieldVarAlias: FieldAlias NumAlias  */
#line 393 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1976 "macroy.c"
    break;

  case 32: /* FieldVarAlias: FieldAlias PareExpListAlias  */
#line 394 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1982 "macroy.c"
    break;

  case 33: /* FieldVarAlias: FieldAlias MacroVarAlias  */
#line 395 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1988 "macroy.c"
    break;

  case 34: /* FieldVarAlias: FieldAlias MacroExprAlias  */
#line 396 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 1994 "macroy.c"
    break;

  case 35: /* AliasId: IDENTIFIER  */
#line 399 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                              { (yyval.asExpr) = hb_compExprNewVar( (yyvsp[0].string), HB_COMP_PARAM ); }
#line 2000 "macroy.c"
    break;

  case 38: /* AliasVar: NumAlias AliasId  */
#line 404 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2006 "macroy.c"
    break;

  case 39: /* AliasVar: MacroVarAlias AliasId  */
#line 405 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2012 "macroy.c"
    break;

  case 40: /* AliasVar: MacroExprAlias AliasId  */
#line 406 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2018 "macroy.c"
    break;

  case 41: /* AliasVar: PareExpListAlias AliasId  */
#line 407 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2024 "macroy.c"
    break;

  case 42: /* AliasVar: VarAlias AliasId  */
#line 408 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2030 "macroy.c"
    break;

  case 43: /* AliasVar: FieldAlias AliasId  */
#line 409 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2036 "macroy.c"
    break;

  case 44: /* AliasVar: FieldVarAlias AliasId  */
#line 410 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewAliasVar( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2042 "macroy.c"
    break;

  case 45: /* AliasExpr: NumAlias PareExpList  */
#line 419 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAliasExpr( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2048 "macroy.c"
    break;

  case 46: /* AliasExpr: VarAlias PareExpList  */
#line 420 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAliasExpr( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2054 "macroy.c"
    break;

  case 47: /* AliasExpr: MacroVarAlias PareExpList  */
#line 421 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAliasExpr( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2060 "macroy.c"
    break;

  case 48: /* AliasExpr: MacroExprAlias PareExpList  */
#line 422 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAliasExpr( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2066 "macroy.c"
    break;

  case 49: /* AliasExpr: PareExpListAlias PareExpList  */
#line 423 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewAliasExpr( (yyvsp[-1].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2072 "macroy.c"
    break;

  case 50: /* VariableAt: NumValue ArrayIndex  */
#line 428 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2078 "macroy.c"
    break;

  case 51: /* VariableAt: NilValue ArrayIndex  */
#line 429 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2084 "macroy.c"
    break;

  case 52: /* VariableAt: DateValue ArrayIndex  */
#line 430 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2090 "macroy.c"
    break;

  case 53: /* VariableAt: TimeStampValue ArrayIndex  */
#line 431 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2096 "macroy.c"
    break;

  case 54: /* VariableAt: LiteralValue ArrayIndex  */
#line 432 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2102 "macroy.c"
    break;

  case 55: /* VariableAt: CodeBlock ArrayIndex  */
#line 433 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2108 "macroy.c"
    break;

  case 56: /* VariableAt: Logical ArrayIndex  */
#line 434 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2114 "macroy.c"
    break;

  case 57: /* VariableAt: Hash ArrayIndex  */
#line 435 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2120 "macroy.c"
    break;

  case 58: /* VariableAt: SelfValue ArrayIndex  */
#line 436 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2126 "macroy.c"
    break;

  case 59: /* VariableAt: Variable ArrayIndex  */
#line 437 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2132 "macroy.c"
    break;

  case 60: /* VariableAt: AliasVar ArrayIndex  */
#line 438 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2138 "macroy.c"
    break;

  case 61: /* VariableAt: AliasExpr ArrayIndex  */
#line 439 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2144 "macroy.c"
    break;

  case 62: /* VariableAt: MacroVar ArrayIndex  */
#line 440 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2150 "macroy.c"
    break;

  case 63: /* VariableAt: MacroExpr ArrayIndex  */
#line 441 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2156 "macroy.c"
    break;

  case 64: /* VariableAt: ObjectData ArrayIndex  */
#line 442 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2162 "macroy.c"
    break;

  case 65: /* VariableAt: ObjectMethod ArrayIndex  */
#line 443 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2168 "macroy.c"
    break;

  case 66: /* VariableAt: FunCall ArrayIndex  */
#line 444 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2174 "macroy.c"
    break;

  case 67: /* VariableAt: IfInline ArrayIndex  */
#line 445 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2180 "macroy.c"
    break;

  case 68: /* VariableAt: PareExpList ArrayIndex  */
#line 446 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2186 "macroy.c"
    break;

  case 69: /* FunCall: IDENTIFIER '(' ArgList ')'  */
#line 451 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_macroExprNewFunCall( hb_compExprNewFunName( (yyvsp[-3].string), HB_COMP_PARAM ), (yyvsp[-1].asExpr), HB_COMP_PARAM );
                                            HB_MACRO_CHECK( (yyval.asExpr) );
                                          }
#line 2194 "macroy.c"
    break;

  case 70: /* FunCall: MacroVar '(' ArgList ')'  */
#line 454 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_macroExprNewFunCall( (yyvsp[-3].asExpr), (yyvsp[-1].asExpr), HB_COMP_PARAM );
                                            HB_MACRO_CHECK( (yyval.asExpr) );
                                          }
#line 2202 "macroy.c"
    break;

  case 71: /* FunRef: '@' IDENTIFIER '(' ArgList ')'  */
#line 459 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             {  if( hb_compExprParamListLen( (yyvsp[-1].asExpr) ) != 0 )
                                                {
                                                   hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
                                                   YYABORT;
                                                }
                                                else
                                                   (yyval.asExpr) = hb_compExprNewFunRef( (yyvsp[-3].string), HB_COMP_PARAM );
                                             }
#line 2215 "macroy.c"
    break;

  case 72: /* ArgList: ExtArgument  */
#line 469 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewArgList( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2221 "macroy.c"
    break;

  case 73: /* ArgList: ArgList ',' ExtArgument  */
#line 470 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprAddListExpr( (yyvsp[-2].asExpr), (yyvsp[0].asExpr) ); }
#line 2227 "macroy.c"
    break;

  case 76: /* RefArgument: '@' IDENTIFIER  */
#line 477 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewVarRef( (yyvsp[0].string), HB_COMP_PARAM ); }
#line 2233 "macroy.c"
    break;

  case 77: /* RefArgument: '@' MacroVar  */
#line 478 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewRef( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2239 "macroy.c"
    break;

  case 78: /* RefArgument: '@' AliasVar  */
#line 479 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewRef( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2245 "macroy.c"
    break;

  case 79: /* RefArgument: '@' ObjectData  */
#line 480 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewRef( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2251 "macroy.c"
    break;

  case 80: /* RefArgument: '@' VariableAt  */
#line 481 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr); (yyval.asExpr)->value.asList.reference = HB_TRUE; }
#line 2257 "macroy.c"
    break;

  case 81: /* ExtArgument: EPSILON  */
#line 484 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                       { (yyval.asExpr) = hb_compExprNewArgRef( HB_COMP_PARAM ); }
#line 2263 "macroy.c"
    break;

  case 83: /* ObjectData: LeftExpression ':' SendId  */
#line 490 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprNewMethodObject( (yyvsp[0].asExpr), (yyvsp[-2].asExpr) ); }
#line 2269 "macroy.c"
    break;

  case 84: /* SendId: IDENTIFIER  */
#line 493 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                             { (yyval.asExpr) = hb_compExprNewSend( (yyvsp[0].string), HB_COMP_PARAM ); }
#line 2275 "macroy.c"
    break;

  case 85: /* SendId: MacroVar  */
#line 494 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                             { (yyval.asExpr) = hb_compExprNewMacroSend( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2281 "macroy.c"
    break;

  case 86: /* SendId: MacroExpr  */
#line 495 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                             { (yyval.asExpr) = hb_compExprNewMacroSend( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2287 "macroy.c"
    break;

  case 87: /* ObjectMethod: ObjectData '(' ArgList ')'  */
#line 500 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewMethodCall( (yyvsp[-3].asExpr), (yyvsp[-1].asExpr) ); }
#line 2293 "macroy.c"
    break;

  case 110: /* SimpleExpression: ExprOperEq  */
#line 526 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { HB_MACRO_IFENABLED( (yyval.asExpr), (yyvsp[0].asExpr), HB_SM_HARBOUR ); }
#line 2299 "macroy.c"
    break;

  case 111: /* SimpleExpression: ExprPostOp  */
#line 527 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { HB_MACRO_IFENABLED( (yyval.asExpr), (yyvsp[0].asExpr), HB_SM_HARBOUR ); }
#line 2305 "macroy.c"
    break;

  case 112: /* SimpleExpression: ExprPreOp  */
#line 528 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { HB_MACRO_IFENABLED( (yyval.asExpr), (yyvsp[0].asExpr), HB_SM_HARBOUR ); }
#line 2311 "macroy.c"
    break;

  case 118: /* Expression: SimpleExpression  */
#line 536 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = (yyvsp[0].asExpr); HB_MACRO_CHECK( (yyval.asExpr) ); }
#line 2317 "macroy.c"
    break;

  case 119: /* Expression: PareExpList  */
#line 537 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = (yyvsp[0].asExpr); HB_MACRO_CHECK( (yyval.asExpr) ); }
#line 2323 "macroy.c"
    break;

  case 120: /* ExtExpression: EPSILON  */
#line 540 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { (yyval.asExpr) = hb_compExprNewArgRef( HB_COMP_PARAM ); }
#line 2329 "macroy.c"
    break;

  case 122: /* $@1: %empty  */
#line 544 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    {
                                       if( !( HB_MACRO_DATA->Flags & HB_MACRO_GEN_LIST ) )
                                       {
                                          HB_TRACE( HB_TR_DEBUG, ( "macro -> invalid expression: %s", HB_MACRO_DATA->string ) );
                                          hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
                                          YYABORT;
                                       }
                                    }
#line 2342 "macroy.c"
    break;

  case 123: /* RootParamList: EmptyExpression ',' $@1 EmptyExpression  */
#line 552 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    {
                                       HB_MACRO_DATA->uiListElements = 1;
                                       (yyval.asExpr) = hb_compExprAddListExpr( ( HB_MACRO_DATA->Flags & HB_MACRO_GEN_PARE ) ? hb_compExprNewList( (yyvsp[-3].asExpr), HB_COMP_PARAM ) : hb_compExprNewArgList( (yyvsp[-3].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr) );
                                    }
#line 2351 "macroy.c"
    break;

  case 125: /* AsParamList: AsParamList ',' EmptyExpression  */
#line 559 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { HB_MACRO_DATA->uiListElements++;
                                                  (yyval.asExpr) = hb_compExprAddListExpr( (yyvsp[-2].asExpr), (yyvsp[0].asExpr) ); }
#line 2358 "macroy.c"
    break;

  case 126: /* EmptyExpression: %empty  */
#line 563 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewEmpty( HB_COMP_PARAM ); }
#line 2364 "macroy.c"
    break;

  case 148: /* LeftExpression: ObjectData  */
#line 587 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                    { HB_MACRO_IFENABLED( (yyval.asExpr), (yyvsp[0].asExpr), HB_SM_HARBOUR ); }
#line 2370 "macroy.c"
    break;

  case 150: /* PostOp: INC  */
#line 594 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                     { (yyval.asExpr) = hb_compExprNewPostInc( (yyvsp[-1].asExpr), HB_COMP_PARAM ); }
#line 2376 "macroy.c"
    break;

  case 151: /* PostOp: DEC  */
#line 595 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                     { (yyval.asExpr) = hb_compExprNewPostDec( (yyvsp[-1].asExpr), HB_COMP_PARAM ); }
#line 2382 "macroy.c"
    break;

  case 152: /* ExprPostOp: LeftExpression PostOp  */
#line 601 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2388 "macroy.c"
    break;

  case 153: /* ExprPreOp: INC Expression  */
#line 604 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewPreInc( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2394 "macroy.c"
    break;

  case 154: /* ExprPreOp: DEC Expression  */
#line 605 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewPreDec( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2400 "macroy.c"
    break;

  case 155: /* ExprUnary: NOT Expression  */
#line 608 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewNot( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2406 "macroy.c"
    break;

  case 156: /* ExprUnary: '-' Expression  */
#line 609 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = hb_compExprNewNegate( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2412 "macroy.c"
    break;

  case 157: /* ExprUnary: '+' Expression  */
#line 610 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                             { (yyval.asExpr) = (yyvsp[0].asExpr); }
#line 2418 "macroy.c"
    break;

  case 158: /* ExprAssign: LeftExpression INASSIGN Expression  */
#line 613 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprAssign( (yyvsp[-2].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2424 "macroy.c"
    break;

  case 159: /* ExprPlusEq: LeftExpression PLUSEQ Expression  */
#line 616 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewPlusEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2430 "macroy.c"
    break;

  case 160: /* ExprMinusEq: LeftExpression MINUSEQ Expression  */
#line 619 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewMinusEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2436 "macroy.c"
    break;

  case 161: /* ExprMultEq: LeftExpression MULTEQ Expression  */
#line 622 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewMultEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2442 "macroy.c"
    break;

  case 162: /* ExprDivEq: LeftExpression DIVEQ Expression  */
#line 625 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewDivEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2448 "macroy.c"
    break;

  case 163: /* ExprModEq: LeftExpression MODEQ Expression  */
#line 628 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewModEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2454 "macroy.c"
    break;

  case 164: /* ExprExpEq: LeftExpression EXPEQ Expression  */
#line 631 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                 { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewExpEq( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2460 "macroy.c"
    break;

  case 171: /* ExprMath: Expression '+' Expression  */
#line 642 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewPlus( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2466 "macroy.c"
    break;

  case 172: /* ExprMath: Expression '-' Expression  */
#line 643 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewMinus( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2472 "macroy.c"
    break;

  case 173: /* ExprMath: Expression '*' Expression  */
#line 644 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewMult( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2478 "macroy.c"
    break;

  case 174: /* ExprMath: Expression '/' Expression  */
#line 645 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewDiv( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2484 "macroy.c"
    break;

  case 175: /* ExprMath: Expression '%' Expression  */
#line 646 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewMod( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2490 "macroy.c"
    break;

  case 176: /* ExprMath: Expression POWER Expression  */
#line 647 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                            { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewPower( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2496 "macroy.c"
    break;

  case 177: /* ExprBool: Expression AND Expression  */
#line 650 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewAnd( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2502 "macroy.c"
    break;

  case 178: /* ExprBool: Expression OR Expression  */
#line 651 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewOr( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2508 "macroy.c"
    break;

  case 179: /* ExprRelation: Expression EQ Expression  */
#line 654 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewEQ( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2514 "macroy.c"
    break;

  case 180: /* ExprRelation: Expression '<' Expression  */
#line 655 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewLT( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2520 "macroy.c"
    break;

  case 181: /* ExprRelation: Expression '>' Expression  */
#line 656 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewGT( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2526 "macroy.c"
    break;

  case 182: /* ExprRelation: Expression LE Expression  */
#line 657 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewLE( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2532 "macroy.c"
    break;

  case 183: /* ExprRelation: Expression GE Expression  */
#line 658 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewGE( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2538 "macroy.c"
    break;

  case 184: /* ExprRelation: Expression NE1 Expression  */
#line 659 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewNE( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2544 "macroy.c"
    break;

  case 185: /* ExprRelation: Expression NE2 Expression  */
#line 660 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewNE( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2550 "macroy.c"
    break;

  case 186: /* ExprRelation: Expression '$' Expression  */
#line 661 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewIN( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2556 "macroy.c"
    break;

  case 187: /* ExprRelation: Expression '=' Expression  */
#line 662 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprSetOperand( hb_compExprNewEqual( (yyvsp[-2].asExpr), HB_COMP_PARAM ), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2562 "macroy.c"
    break;

  case 189: /* IndexList: '[' ExtExpression  */
#line 671 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = hb_macroExprNewArrayAt( (yyvsp[-2].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2568 "macroy.c"
    break;

  case 190: /* IndexList: IndexList ',' ExtExpression  */
#line 672 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = hb_macroExprNewArrayAt( (yyvsp[-2].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2574 "macroy.c"
    break;

  case 191: /* IndexList: IndexList ']' '[' ExtExpression  */
#line 673 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                                { (yyval.asExpr) = hb_macroExprNewArrayAt( (yyvsp[-3].asExpr), (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2580 "macroy.c"
    break;

  case 192: /* ElemList: ExtArgument  */
#line 676 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprNewList( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2586 "macroy.c"
    break;

  case 193: /* ElemList: ElemList ',' ExtArgument  */
#line 677 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                       { (yyval.asExpr) = hb_compExprAddListExpr( (yyvsp[-2].asExpr), (yyvsp[0].asExpr) ); }
#line 2592 "macroy.c"
    break;

  case 194: /* @2: %empty  */
#line 681 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                  { (yyval.asExpr) = hb_compExprNewCodeBlock( NULL, 0, 0, HB_COMP_PARAM ); }
#line 2598 "macroy.c"
    break;

  case 195: /* CodeBlock: '{' '|' @2 BlockVars '|' BlockExpList '}'  */
#line 683 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                  { (yyval.asExpr) = (yyvsp[-4].asExpr); }
#line 2604 "macroy.c"
    break;

  case 196: /* BlockExpList: Expression  */
#line 688 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprAddCodeblockExpr( (yyvsp[(-2) - (1)].asExpr), (yyvsp[0].asExpr) ); }
#line 2610 "macroy.c"
    break;

  case 197: /* BlockExpList: BlockExpList ',' Expression  */
#line 689 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprAddCodeblockExpr( (yyvsp[(-2) - (3)].asExpr), (yyvsp[0].asExpr) ); }
#line 2616 "macroy.c"
    break;

  case 198: /* BlockVars: %empty  */
#line 694 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = NULL; }
#line 2622 "macroy.c"
    break;

  case 199: /* BlockVars: EPSILON  */
#line 695 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = NULL; (yyvsp[-1].asExpr)->value.asCodeblock.flags |= HB_BLOCK_VPARAMS; }
#line 2628 "macroy.c"
    break;

  case 200: /* BlockVars: BlockVarList  */
#line 696 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[0].asExpr);   }
#line 2634 "macroy.c"
    break;

  case 201: /* BlockVars: BlockVarList ',' EPSILON  */
#line 697 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = (yyvsp[-2].asExpr);   (yyvsp[-3].asExpr)->value.asCodeblock.flags |= HB_BLOCK_VPARAMS; }
#line 2640 "macroy.c"
    break;

  case 202: /* BlockVarList: IDENTIFIER  */
#line 700 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprCBVarAdd( (yyvsp[-1].asExpr), (yyvsp[0].string), ' ', HB_COMP_PARAM ); }
#line 2646 "macroy.c"
    break;

  case 203: /* BlockVarList: BlockVarList ',' IDENTIFIER  */
#line 701 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                          { (yyval.asExpr) = hb_compExprCBVarAdd( (yyvsp[-3].asExpr), (yyvsp[0].string), ' ', HB_COMP_PARAM ); HB_MACRO_CHECK( (yyval.asExpr) ); }
#line 2652 "macroy.c"
    break;

  case 204: /* ExpList: '(' EmptyExpression  */
#line 704 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                           { (yyval.asExpr) = hb_compExprNewList( (yyvsp[0].asExpr), HB_COMP_PARAM ); }
#line 2658 "macroy.c"
    break;

  case 205: /* ExpList: ExpList ',' EmptyExpression  */
#line 705 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
                                           { (yyval.asExpr) = hb_compExprAddListExpr( (yyvsp[-2].asExpr), (yyvsp[0].asExpr) ); }
#line 2664 "macroy.c"
    break;

  case 208: /* IfInline: IIF '(' Expression ',' Argument ',' Argument ')'  */
#line 716 "c:\\temp\\harbour-core\\src\\macro\\macro.y"
               { (yyval.asExpr) = hb_compExprNewIIF( hb_compExprAddListExpr( hb_compExprAddListExpr( hb_compExprNewList( (yyvsp[-5].asExpr), HB_COMP_PARAM ), (yyvsp[-3].asExpr) ), (yyvsp[-1].asExpr) ) ); }
#line 2670 "macroy.c"
    break;


#line 2674 "macroy.c"

      default: break;
    }
  /* User semantic actions sometimes alter yychar, and that requires
     that yytoken be updated with the new translation.  We take the
     approach of translating immediately before every use of yytoken.
     One alternative is translating here after every semantic action,
     but that translation would be missed if the semantic action invokes
     YYABORT, YYACCEPT, or YYERROR immediately after altering yychar or
     if it invokes YYBACKUP.  In the case of YYABORT or YYACCEPT, an
     incorrect destructor might then be invoked immediately.  In the
     case of YYERROR or YYBACKUP, subsequent parser actions might lead
     to an incorrect destructor call or verbose syntax error message
     before the lookahead is translated.  */
  YY_SYMBOL_PRINT ("-> $$ =", YY_CAST (yysymbol_kind_t, yyr1[yyn]), &yyval, &yyloc);

  YYPOPSTACK (yylen);
  yylen = 0;

  *++yyvsp = yyval;

  /* Now 'shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */
  {
    const int yylhs = yyr1[yyn] - YYNTOKENS;
    const int yyi = yypgoto[yylhs] + *yyssp;
    yystate = (0 <= yyi && yyi <= YYLAST && yycheck[yyi] == *yyssp
               ? yytable[yyi]
               : yydefgoto[yylhs]);
  }

  goto yynewstate;


/*--------------------------------------.
| yyerrlab -- here on detecting error.  |
`--------------------------------------*/
yyerrlab:
  /* Make sure we have latest lookahead translation.  See comments at
     user semantic actions for why this is necessary.  */
  yytoken = yychar == HB_MACRO_YYEMPTY ? YYSYMBOL_YYEMPTY : YYTRANSLATE (yychar);
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
      yyerror (pMacro, YY_("syntax error"));
    }

  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse lookahead token after an
         error, discard it.  */

      if (yychar <= HB_MACRO_YYEOF)
        {
          /* Return failure if at end of input.  */
          if (yychar == HB_MACRO_YYEOF)
            YYABORT;
        }
      else
        {
          yydestruct ("Error: discarding",
                      yytoken, &yylval, pMacro);
          yychar = HB_MACRO_YYEMPTY;
        }
    }

  /* Else will try to reuse lookahead token after shifting the error
     token.  */
  goto yyerrlab1;


/*---------------------------------------------------.
| yyerrorlab -- error raised explicitly by YYERROR.  |
`---------------------------------------------------*/
yyerrorlab:
  /* Pacify compilers when the user code never invokes YYERROR and the
     label yyerrorlab therefore never appears in user code.  */
  if (0)
    YYERROR;
  ++yynerrs;

  /* Do not reclaim the symbols of the rule whose action triggered
     this YYERROR.  */
  YYPOPSTACK (yylen);
  yylen = 0;
  YY_STACK_PRINT (yyss, yyssp);
  yystate = *yyssp;
  goto yyerrlab1;


/*-------------------------------------------------------------.
| yyerrlab1 -- common code for both syntax error and YYERROR.  |
`-------------------------------------------------------------*/
yyerrlab1:
  yyerrstatus = 3;      /* Each real token shifted decrements this.  */

  /* Pop stack until we find a state that shifts the error token.  */
  for (;;)
    {
      yyn = yypact[yystate];
      if (!yypact_value_is_default (yyn))
        {
          yyn += YYSYMBOL_YYerror;
          if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYSYMBOL_YYerror)
            {
              yyn = yytable[yyn];
              if (0 < yyn)
                break;
            }
        }

      /* Pop the current state because it cannot handle the error token.  */
      if (yyssp == yyss)
        YYABORT;


      yydestruct ("Error: popping",
                  YY_ACCESSING_SYMBOL (yystate), yyvsp, pMacro);
      YYPOPSTACK (1);
      yystate = *yyssp;
      YY_STACK_PRINT (yyss, yyssp);
    }

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END


  /* Shift the error token.  */
  YY_SYMBOL_PRINT ("Shifting", YY_ACCESSING_SYMBOL (yyn), yyvsp, yylsp);

  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturnlab;


/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturnlab;


/*-----------------------------------------------------------.
| yyexhaustedlab -- YYNOMEM (memory exhaustion) comes here.  |
`-----------------------------------------------------------*/
yyexhaustedlab:
  yyerror (pMacro, YY_("memory exhausted"));
  yyresult = 2;
  goto yyreturnlab;


/*----------------------------------------------------------.
| yyreturnlab -- parsing is finished, clean up and return.  |
`----------------------------------------------------------*/
yyreturnlab:
  if (yychar != HB_MACRO_YYEMPTY)
    {
      /* Make sure we have latest lookahead translation.  See comments at
         user semantic actions for why this is necessary.  */
      yytoken = YYTRANSLATE (yychar);
      yydestruct ("Cleanup: discarding lookahead",
                  yytoken, &yylval, pMacro);
    }
  /* Do not reclaim the symbols of the rule whose action triggered
     this YYABORT or YYACCEPT.  */
  YYPOPSTACK (yylen);
  YY_STACK_PRINT (yyss, yyssp);
  while (yyssp != yyss)
    {
      yydestruct ("Cleanup: popping",
                  YY_ACCESSING_SYMBOL (+*yyssp), yyvsp, pMacro);
      YYPOPSTACK (1);
    }
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif

  return yyresult;
}

#line 719 "c:\\temp\\harbour-core\\src\\macro\\macro.y"



/*
 ** ------------------------------------------------------------------------ **
 */

void yyerror( PHB_MACRO pMacro, const char * s )
{
   HB_SYMBOL_UNUSED( pMacro );
   HB_SYMBOL_UNUSED( s );
}

/* ************************************************************************* */

#define HB_MEXPR_PREALLOC 8

typedef struct HB_MEXPR_
{
   int      count;
   HB_EXPR  Expressions[ HB_MEXPR_PREALLOC ];
   struct HB_MEXPR_ *pPrev;
}
HB_MEXPR, * PHB_MEXPR;

typedef struct HB_MIDENT_
{
   char * Identifier;
   struct HB_MIDENT_ * pPrev;
}
HB_MIDENT, * PHB_MIDENT;

/* Allocates memory for Expression holder structure and stores it
 * on the linked list
*/
static PHB_EXPR hb_macroExprAlloc( HB_COMP_DECL )
{
   PHB_MEXPR pMExpr = ( PHB_MEXPR ) HB_MACRO_DATA->pExprLst;

   if( ! pMExpr || pMExpr->count >= HB_MEXPR_PREALLOC )
   {
      pMExpr = ( PHB_MEXPR ) hb_xgrab( sizeof( HB_MEXPR ) );
      pMExpr->pPrev = ( PHB_MEXPR ) HB_MACRO_DATA->pExprLst;
      pMExpr->count = 0;
      HB_MACRO_DATA->pExprLst = ( void * ) pMExpr;
   }
   return &pMExpr->Expressions[ pMExpr->count++ ];
}

char * hb_macroIdentNew( HB_COMP_DECL, char * szIdent )
{
   PHB_MIDENT pMIdent = ( PHB_MIDENT ) hb_xgrab( sizeof( HB_MIDENT ) );

   pMIdent->Identifier = szIdent;
   pMIdent->pPrev = ( PHB_MIDENT ) HB_MACRO_DATA->pIdentLst;
   HB_MACRO_DATA->pIdentLst = ( void * ) pMIdent;

   return szIdent;
}

static PHB_EXPR hb_macroExprNew( HB_COMP_DECL, HB_EXPRTYPE iType )
{
   PHB_EXPR pExpr;

   HB_TRACE( HB_TR_DEBUG, ( "hb_macroExprNew(%p,%i)", ( void * ) HB_COMP_PARAM, iType ) );

   pExpr = hb_macroExprAlloc( HB_COMP_PARAM );
   pExpr->ExprType = iType;
   pExpr->pNext    = NULL;
   pExpr->ValType  = HB_EV_UNKNOWN;

   return pExpr;
}

/* Delete self - all components will be deleted somewhere else
 */
static void hb_macroExprClear( HB_COMP_DECL, PHB_EXPR pExpr )
{
   HB_SYMBOL_UNUSED( HB_COMP_PARAM );

   pExpr->ExprType = HB_ET_NONE;
}

/* Delete all components and delete self
 */
static void hb_macroExprFree( HB_COMP_DECL, PHB_EXPR pExpr )
{
   HB_TRACE( HB_TR_DEBUG, ( "hb_macroExprFree()" ) );

   HB_EXPR_USE( pExpr, HB_EA_DELETE );
   pExpr->ExprType = HB_ET_NONE;
}

/* Deallocate all memory used by expression optimizer */
static void hb_macroLstFree( PHB_MACRO pMacro )
{
   if( pMacro->pExprLst )
   {
      PHB_MEXPR pMExpr = ( PHB_MEXPR ) pMacro->pExprLst;
      do
      {
         while( pMExpr->count )
            hb_macroExprFree( pMacro, &pMExpr->Expressions[ --pMExpr->count ] );
         pMExpr = pMExpr->pPrev;
      }
      while( pMExpr );
      do
      {
         pMExpr = ( PHB_MEXPR ) pMacro->pExprLst;
         pMacro->pExprLst = ( void * ) pMExpr->pPrev;
         hb_xfree( pMExpr );
      }
      while( pMacro->pExprLst );
   }

   while( pMacro->pIdentLst )
   {
      PHB_MIDENT pMIdent = ( PHB_MIDENT ) HB_MACRO_DATA->pIdentLst;
      HB_MACRO_DATA->pIdentLst = ( void * ) pMIdent->pPrev;
      hb_xfree( pMIdent->Identifier );
      hb_xfree( pMIdent );
   }
}

static PHB_EXPR hb_macroErrorType( HB_COMP_DECL, PHB_EXPR pExpr )
{
   hb_macroError( EG_ARG, HB_COMP_PARAM );
   return pExpr;
}

static PHB_EXPR hb_macroErrorSyntax( HB_COMP_DECL, PHB_EXPR pExpr )
{
   hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
   return pExpr;
}

static void hb_macroErrorDuplVar( HB_COMP_DECL, const char * szVarName )
{
   HB_SYMBOL_UNUSED( szVarName );
   hb_macroError( EG_SYNTAX, HB_COMP_PARAM );
}


static const HB_COMP_FUNCS s_macro_funcs =
{
   hb_macroExprNew,
   hb_macroExprClear,
   hb_macroExprFree,

   hb_macroErrorType,
   hb_macroErrorSyntax,
   hb_macroErrorDuplVar,
};

int hb_macroYYParse( PHB_MACRO pMacro )
{
   int iResult;

   pMacro->funcs = &s_macro_funcs;

   if( hb_macroLexNew( pMacro ) )
   {
      pMacro->status = HB_MACRO_CONT;
      pMacro->pExprLst = NULL;
      pMacro->pIdentLst = NULL;

      iResult = yyparse( pMacro );

      hb_macroLstFree( pMacro );
      hb_macroLexDelete( pMacro );
   }
   else
      iResult = HB_MACRO_FAILURE;

   return iResult;
}


#if defined( HB_MACRO_PPLEX )

/* it's an example of PP token translator which change tokens generated by
   PP into terminal symbols used by our grammar parser generated by Bison */
HB_BOOL hb_macroLexNew( PHB_MACRO pMacro )
{
   pMacro->pLex = ( void * ) hb_pp_lexNew( pMacro->string, pMacro->length );
   return pMacro->pLex != NULL;
}

void hb_macroLexDelete( PHB_MACRO pMacro )
{
   if( pMacro->pLex )
   {
      hb_pp_free( ( PHB_PP_STATE ) pMacro->pLex );
      pMacro->pLex = NULL;
   }
}

int hb_macro_yylex( YYSTYPE * yylval_ptr, PHB_MACRO pMacro )
{
   PHB_PP_TOKEN pToken = hb_pp_lexGet( ( PHB_PP_STATE ) pMacro->pLex );

   if( ! pToken )
      return 0;

   switch( HB_PP_TOKEN_TYPE( pToken->type ) )
   {
      case HB_PP_TOKEN_KEYWORD:
         if( pToken->len >= 4 && pToken->len <= 6 && pToken->pNext &&
             HB_PP_TOKEN_TYPE( pToken->pNext->type ) == HB_PP_TOKEN_ALIAS &&
             ( hb_strnicmp( "_FIELD", pToken->value, pToken->len ) == 0 ||
               hb_strnicmp( "FIELD", pToken->value, pToken->len ) == 0 ) )
         {
            return FIELD;
         }
         else if( pToken->len == 3 && pToken->pNext &&
                  HB_PP_TOKEN_TYPE( pToken->pNext->type ) == HB_PP_TOKEN_LEFT_PB &&
                  hb_stricmp( "IIF", pToken->value ) == 0 )
         {
            return IIF;
         }
         else if( pToken->len == 2 && pToken->pNext &&
                  HB_PP_TOKEN_TYPE( pToken->pNext->type ) == HB_PP_TOKEN_LEFT_PB &&
                  hb_stricmp( "IF", pToken->value ) == 0 )
            return IIF;
         else if( pToken->len == 3 && hb_stricmp( "NIL", pToken->value ) == 0 )
            return NIL;

         hb_pp_tokenUpper( pToken );
         yylval_ptr->string = pToken->value;
         return IDENTIFIER;

      case HB_PP_TOKEN_MACROVAR:
         hb_pp_tokenUpper( pToken );
         yylval_ptr->string = pToken->value;
         return MACROVAR;

      case HB_PP_TOKEN_MACROTEXT:
         hb_pp_tokenUpper( pToken );
         yylval_ptr->string = pToken->value;
         return MACROTEXT;

      case HB_PP_TOKEN_NUMBER:
      {
         HB_MAXINT lNumber;
         double dNumber;
         int iDec, iWidth;

         if( hb_compStrToNum( pToken->value, pToken->len, &lNumber, &dNumber, &iDec, &iWidth ) )
         {
            yylval_ptr->valDouble.dNumber = dNumber;
            yylval_ptr->valDouble.bDec    = ( HB_UCHAR ) iDec;
            yylval_ptr->valDouble.bWidth  = ( HB_UCHAR ) iWidth;
            return NUM_DOUBLE;
         }
         else
         {
            yylval_ptr->valLong.lNumber = lNumber;
            yylval_ptr->valLong.bWidth  = ( HB_UCHAR ) iWidth;
            return NUM_LONG;
         }
      }
      case HB_PP_TOKEN_DATE:
         if( pToken->len == 10 )
         {
            int year, month, day;
            hb_dateStrGet( pToken->value + 2, &year, &month, &day );
            yylval_ptr->valLong.lNumber = hb_dateEncode( year, month, day );
         }
         else
            yylval_ptr->valLong.lNumber = 0;
         return NUM_DATE;

      case HB_PP_TOKEN_TIMESTAMP:
         if( ! hb_timeStampStrGetDT( pToken->value,
                                     &yylval_ptr->valTimeStamp.date,
                                     &yylval_ptr->valTimeStamp.time ) )
         {
            hb_macroError( EG_SYNTAX, pMacro );
         }
         return TIMESTAMP;

      case HB_PP_TOKEN_STRING:
         yylval_ptr->valChar.string = pToken->value;
         yylval_ptr->valChar.length = pToken->len;
         return LITERAL;

      case HB_PP_TOKEN_LOGICAL:
         return pToken->value[ 1 ] == 'T' ? TRUEVALUE : FALSEVALUE;

      case HB_PP_TOKEN_HASH:
      case HB_PP_TOKEN_DIRECTIVE:
         return NE1;

      case HB_PP_TOKEN_NE:
         return NE2;

      case HB_PP_TOKEN_ASSIGN:
         return INASSIGN;

      case HB_PP_TOKEN_EQUAL:
         return EQ;

      case HB_PP_TOKEN_INC:
         return INC;

      case HB_PP_TOKEN_DEC:
         return DEC;

      case HB_PP_TOKEN_ALIAS:
         return ALIASOP;

      case HB_PP_TOKEN_LE:
         return LE;

      case HB_PP_TOKEN_GE:
         return GE;

      case HB_PP_TOKEN_PLUSEQ:
         return PLUSEQ;

      case HB_PP_TOKEN_MINUSEQ:
         return MINUSEQ;

      case HB_PP_TOKEN_MULTEQ:
         return MULTEQ;

      case HB_PP_TOKEN_DIVEQ:
         return DIVEQ;

      case HB_PP_TOKEN_MODEQ:
         return MODEQ;

      case HB_PP_TOKEN_EXPEQ:
         return EXPEQ;

      case HB_PP_TOKEN_POWER:
         return POWER;

      case HB_PP_TOKEN_AND:
         return AND;

      case HB_PP_TOKEN_OR:
         return OR;

      case HB_PP_TOKEN_NOT:
         return NOT;

      default:
         return pToken->value[ 0 ];
   }
}

#endif /* HB_MACRO_PPLEX */
