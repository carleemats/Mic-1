/* JVM simulator written in ARM Assembly implementing Tanenbaum's Mic-1 */

/*
============================= EXTERNAL FUNCTIONS =============================
 */
.extern fgetc
.extern fopen
.extern puts
.extern printf
.extern fclose
.extern __aeabi_idiv

/*
============================= MIC-1 REGISTERS =============================
 */
mic1_OPC .req r2                    /* Holds temporary PC */
mic1_MBRU .req r3                   /* Value accessed from bytecode (unsigned) */
mic1_MBR .req r4                    /* Value accessed from bytecode (signed) */
mic1_TOS .req r5                    /* Value at the top of the stack */
mic1_SP .req r6                     /* Address at the top of the stack */
mic1_MDR .req r7                    /* Value that can be written to/from memory */
mic1_MAR .req r8                    /* Address that the MDR is written to and read from */
mic1_PC .req r9                     /* Holds the address of the next bytecode */
mic1_LV .req r10                    /* Address of the first local variable, bottom of stack frame */
mic1_CPP .req r11                   /* Holds the link pointer */
mic1_H .req r12                     /* Holds temporary values */

/*
============================= MACROS =============================
 */
 /* Debug macro to print what you provide in x */
.macro _debug_ x
    push {r0-r3, lr} 
    ldr r0, =format
    ldr r1, =#\x 
    bl printf 
    pop {r0-r3, lr}
.endm

/* Debug macro to print what is in a certain register */
.macro _debug_reg_ x
    push {r0-r3, r12, lr} 
    mov r1, \x
    ldr r0, =format
    bl printf 
    pop {r0-r3, r12, lr}
.endm

/* Getting the next insturction into the MBRU/MBRU using the PC */
.macro _fetch_
    ldrb mic1_MBRU, [mic1_PC]
    ldrsb mic1_MBR, [mic1_PC]
.endm

/* Write what is in the MDR (value) to the location of MAR (address) */
.macro _write_
    str mic1_MDR, [mic1_MAR]
.endm

/* Read in from the location of the MAR to the MDR */
.macro _read_
    ldr mic1_MDR, [mic1_MAR]
.endm

/*
============================= DATA SECTION =============================
 */
.data
.balign 4
array: .skip 4096

.balign 4
currentIndex: .word 0       /* Keep track of where to store the next value in array (memory) */

.balign 4
file: .word 0               /* a FILE pointer */

.balign 4
read: .asciz "r"            /* Read mode */

.balign 4
format: .asciz "%d\n"

/* Error messages */
.balign 4
errorOpcodeMsg: .asciz "ERROR: ILLEGAL OPCODE FOUND\n"

.balign 4
errorArgMsg: .asciz "ERROR: ILLEGAL NUMBER OF ARGUMENTS\n"

.balign 4
errorFileMsg: .asciz "ERROR: ILLEGAL FILE GIVEN\n"

/*
============================= CODE SECTION =============================
 */
.text
.global main
main:
    /* Open a file */
    push {lr}

    cmp r0, #2
    bne errorArg        /* If r0 (number of arguments) does not equal 2, prints error message and exits */

    ldr r0, [r1, #4]    /* r0 has count of args in array
                            * Whose address is in r1; the count should be 2:
                            * ["name of program", "filename"] */

    ldr r1, =read
    bl fopen

    cmp r0, #0
    beq errorFile       /* If r0 holds 0 (file pointer is 0, doesn't exist), prints error message and exits */

    mov r5, r0
    b loop

/* Take single character at a time: fgetc(file pointer) */               
/* While end of file is not reached, read in characters */
loop:
    bl fgetc                    /* Call fgetc on the file pointer in r0 */
    cmp r0, #-1                 /* Compare returned value to -1 (EOF) */
    beq setup

    /* Add instruction to array, NOTE: only increments by 1 */
    ldr r1, addr_array          /* Add instruction to array, NOTE: only increments by 1 */
    ldr r2, addr_currentIndex
    ldr r3, [r2]
    
    add r4, r1, r3
    str r0, [r4]

    add r3, r3, #1
    str r3, [r2]

    mov r0, r5
    b loop                      /* Not EOF, branch to loop */

/* Close the file and set up/initialize special registers */
setup:
    /* Close the file */
    mov r0, r5
    bl fclose

    /* Set up PC to address of 3rd byte in memory (first two bytes are local variables) */
    ldr r0, addr_array
    add mic1_PC, r0, #2

    /* Set up LV register (address of next space after last instruction in stack) */
    ldr r0, addr_array
    ldr r1, addr_currentIndex
    ldr r1, [r1]
    add mic1_LV, r0, r1
    
    /* 
    Combine first and second bytes in array to get number of local variables
    Need this to find space between SP and LV
    */
    ldr r0, addr_array
    ldrb r1, [r0]
    mov r1, r1, ASL #8

    add r0, r0, #1
    ldrb r0, [r0]
    orr r1, r1, r0                  /* Number of local variables (16-bit number) */

    mov r1, r1, LSL #2              /* Need value to be represented as words (multiply by 4) */

    /* Set up SP register, top of stack (after local variables added from the LV register) */
    add mic1_SP, mic1_LV, r1

    /* Set up MBR and MBRU, first instruction using PC */
    ldrsb mic1_MBR, [mic1_PC]
    ldrb mic1_MBRU, [mic1_PC]

    b main1

main1:
    mov r0, mic1_MBRU               /* Use MBRU register for comparison of instructions */
    add mic1_PC, mic1_PC, #1        /* Increment PC */
    ldrsb mic1_MBR, [mic1_PC]       /* Get new instruction, store in MBR/MBRU */
    ldrb mic1_MBRU, [mic1_PC]

    cmp r0, #0x60
    beq iadd
    cmp r0, #0x10
    beq bipush
    cmp r0, #0x36
    beq istore
    cmp r0, #0x15
    beq iload
    cmp r0, #0x68
    beq imul
    cmp r0, #0x64
    beq isub
    cmp r0, #0x6C
    beq idiv
    cmp r0, #0x7E
    beq iand
    cmp r0, #0x80
    beq ior
    cmp r0, #0x84
    beq iinc
    cmp r0, #0x99
    beq ifeq
    cmp r0, #0x9F
    beq if_icmpeq
    cmp r0, #0x9B
    beq iflt
    cmp r0, #0xA7
    beq goto
    cmp r0, #0x57
    beq bipop
    cmp r0, #0x5F
    beq swap
    cmp r0, #0x59
    beq dup
    cmp r0, #0xA8
    beq jsr
    cmp r0, #0xA9
    beq ret

    b errorOpcode               /* If r0 (opcode) doesn't match anything, prints error message and exits */
    b exit

/* IADD: Pops two words from the stack, pushes the sum */
iadd:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    add mic1_TOS, mic1_MDR, mic1_H      /* Perform addition */
    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* BIPUSH (takes a byte): Pushes a byte onto the stack
NOTE: Order changed here, incrementing PC and _fetch_ comes after _write_. In order to go back to main1,
the next opcode needs to be fetched in order to step through properly.
*/ 
bipush:
    add mic1_SP, mic1_SP, #4        /* Save space for local variables */
    mov mic1_MAR, mic1_SP

    mov mic1_TOS, mic1_MBR          /* Copy new TOS */
    mov mic1_MDR, mic1_TOS          /* Byte copied */
    _write_                         /* Byte written back to memory */

    add mic1_PC, mic1_PC, #1        /* Get the next opcode to be fetched */
    _fetch_

    b main1

/* ISTORE (takes a varnum): Pops word from the stack and stores it in a local variable */
istore:
    mov mic1_H, mic1_LV                             /* Copy LV */

    add mic1_MAR, mic1_H, mic1_MBRU, LSL #2         /* Get the address of the local variable to store to (need to multiply by 4, in words) */

    mov mic1_MDR, mic1_TOS                          /* Copy TOS */
    _write_                                         /* Write word to memory */

    sub mic1_MAR, mic1_SP, #4                       /* Read the next word from the stack */
    mov mic1_SP, mic1_MAR

    add mic1_PC, mic1_PC, #1                        /* Get the next opcode to be fetched */
    _fetch_

    mov mic1_TOS, mic1_MDR                          /* Update TOS */

    b main1

/* ILOAD (takes a varnum): Pushes a local variable on the stack */
iload:
    mov mic1_H, mic1_LV                             /* Copy LV */

    add mic1_MAR, mic1_H, mic1_MBRU, LSL #2         /* Get the address of the local variable to push (need to multiply by 4, in words) */
    _read_

    add mic1_SP, mic1_SP, #4                        /* Pointing to new top of stack - SP */
    mov mic1_MAR, mic1_SP                           /* Prepare to call write (uses MAR) */

    add mic1_PC, mic1_PC, #1                        /* Get the next opcode to be fetched */
    _fetch_

    _write_                                         /* Write the local variable to memory */

    mov mic1_TOS, mic1_MDR                          /* Update TOS */

    b main1

/* IMUL: Pops two words from the stack, pushes the product */
imul:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack (after TOS) */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    mul mic1_TOS, mic1_MDR, mic1_H      /* Perform multiplication */
    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* ISUB: Pops two words from the stack, pushes the difference */
isub:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack (after TOS) */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    sub mic1_TOS, mic1_MDR, mic1_H      /* Perform subtraction */
    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* IDIV: Pops two words from the stack, pushes the quotient */
idiv:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    mov r0, mic1_H                      /* Perform division using __aeabi_div C library */
    mov r1, mic1_MDR
    push {r3}                           /* Need to preserve r3 (holds MBRU), r0-r3 gets trashed after external function returns */
    bl __aeabi_idiv
    pop {r3}
    mov mic1_TOS, r0

    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* IAND: Pops two words from the stack, pushes the Boolean AND */
iand:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    and mic1_TOS, mic1_MDR, mic1_H      /* Perform AND */
    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* IOR: Pops two words from the stack, pushes the Boolean OR */
ior:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_H, mic1_TOS                /* Copy TOS */

    orr mic1_TOS, mic1_MDR, mic1_H      /* Perform OR */
    mov mic1_MDR, mic1_TOS              /* Prepare write */
    _write_                             /* Result written back to memory at the top of the stack */

    b main1

/* IINC (takes varnum and const): Add a constant to a local variable */
iinc:
    mov mic1_H, mic1_LV                     /* Copy LV */

    add mic1_MAR, mic1_MBRU, mic1_H         /* Add LV and index (MBRU), prepare read */
    _read_                                  /* Read local variable from memory */

    add mic1_PC, mic1_PC, #1                /* Get the constant to be fetched */
    _fetch_

    mov mic1_H, mic1_MDR                    /* Copy local variable (MDR) to H */

    add mic1_MDR, mic1_MBR, mic1_H          /* Add constant (MBR) to local variable (MDR) */
    _write_                                 /* Result written back to memory, variable updates */

    add mic1_PC, mic1_PC, #1                /* Get the next opcode to be fetched */
    _fetch_

    b main1

/* BIPOP: Deletes the word at the top of the stack */
bipop:
    sub mic1_SP, mic1_SP, #4        /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP           /* Prepare read */
    _read_                          /* Read word from memory */

    mov mic1_TOS, mic1_MDR          /* Copy new word to the top of the stack */

    b main1

/* SWAP: Swaps the two top words on the stack */
swap:
    sub mic1_MAR, mic1_SP, #4       /* Get the next word off the stack */
    _read_                          /* Read the next word from memory (second word) */

    mov mic1_MAR, mic1_SP           /* Set MAR to the top word */

    mov mic1_H, mic1_MDR            /* Save TOS in H */
    _write_                         /* Write the second word to the top of the stack */

    mov mic1_MDR, mic1_TOS          /* Copy the old TOS */

    sub mic1_MAR, mic1_SP, #4
    _write_                         /* Write as second word on the stack */

    mov mic1_TOS, mic1_H            /* Update the new TOS */

    b main1

/* DUP: Copies the top of the word on the stack and pushes it onto the stack */
dup:
    add mic1_SP, mic1_SP, #4        /* Save space for new word */
    mov mic1_MAR, mic1_SP           /* Prepare write */

    mov mic1_TOS, mic1_MDR          /* Update the new TOS */
    _write_                         /* Write the duplicated word to memory */

    b main1

/* IFEQ (takes offset): Pops word from stack and branch if it is 0 */
ifeq:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_OPC, mic1_TOS              /* Copy TOS */

    mov mic1_TOS, mic1_MDR              /* Need to read in a new word from the top of the stack to put in TOS */

    cmp mic1_OPC, #0                    /* If the word is 0, branch to true (goto), else branch to false */
    beq true
    b false

/* IFICMPEQ (takes offset): Pops two words from the stack and branches if they are equal */
if_icmpeq:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read to get the next word */

    mov mic1_H, mic1_MDR                /* Copy the second word from the stack to H */
    _read_                              /* Read second word from memory */

    mov mic1_OPC, mic1_TOS              /* Copy TOS */

    mov mic1_TOS, mic1_MDR              /* Need to read in a new word from the top of the stack to put in TOS */

    sub mic1_OPC, mic1_OPC, mic1_H      /* Perform subtraction to see if two words are equal */
    cmp mic1_OPC, #0                    /* If the words are equal, branch to true (goto), else branch to false */
    beq true
    b false

/* IFLT (takes offset): Pops a word from the stack and branches if it is less than zero */
iflt:
    sub mic1_SP, mic1_SP, #4            /* Get the next word off the stack */
    mov mic1_MAR, mic1_SP               /* Prepare read */
    _read_                              /* Read word from memory */

    mov mic1_OPC, mic1_TOS              /* Copy TOS */

    mov mic1_TOS, mic1_MDR              /* Need to read in a new word from the top of the stack to put in TOS */

    cmp mic1_OPC, #0                    /* If the word is less than 0, branch to true (goto), else branch to false */
    blt true
    b false

true:
    b goto                              /* Immediately branches to goto (goto already handles saving the address of the opcode */

false:
    add mic1_PC, mic1_PC, #1            /* Increment PC to skip the first offset byte */
    add mic1_PC, mic1_PC, #1            /* Get the next opcode to be fetched */
    _fetch_
    b main1

/* GOTO (takes an offset): Unconditional branch
Want to change the value of the PC, so the following instruction executed is the one at
the address computed by adding the (signed) 16-bit offset to the address of the branch opcode
*/
goto:
    sub mic1_OPC, mic1_PC, #1               /* Store previous (old) PC into OPC */

    add mic1_PC, mic1_PC, #1                /* Fetch second offset byte */

    mov mic1_H, mic1_MBR, ASL #8            /* Shift first offset byte 8 bits, copy to H */
    _fetch_
    orr mic1_H, mic1_H, mic1_MBRU

    add mic1_PC, mic1_OPC, mic1_H
    _fetch_                                 /* Main1 expects the next opcode in MBR */

    b main1

/* JSR: (takes num of lcoal vars, num args, high byte and low byte of address of subroutine to jump to)
Implements subroutine calls, return value will be stored in the TOS register
*/
jsr:
    add mic1_SP, mic1_SP, #4                /* Save space for local variables - multiply by 4 (words) */
    add mic1_SP, mic1_SP, mic1_MBRU

    mov mic1_MDR, mic1_CPP                  /* Push the old link pointer */

    mov mic1_CPP, mic1_SP                   /* Set the link pointer */
    mov mic1_MAR, mic1_CPP
    _write_

    add mic1_MDR, mic1_PC, #4               /* Push return PC */

    add mic1_SP, mic1_SP, #4
    mov mic1_MAR, mic1_SP
    _write_

    mov mic1_MDR, mic1_LV                   /* Push old LV */

    add mic1_SP, mic1_SP, #4
    mov mic1_MAR, mic1_SP
    _write_

    sub mic1_LV, mic1_SP, #8
    sub mic1_LV, mic1_LV, mic1_MBRU         /* Set the new LV */

    add mic1_PC, mic1_PC, #1
    _fetch_                                 /* Get number of args */

    sub mic1_LV, mic1_LV, mic1_MBRU         /* Adjust LB to first argument */

    add mic1_PC, mic1_PC, #1                /* Get the high byte of the address */
    _fetch_

    mov mic1_H, mic1_MBR, ASL #8            /* Shift and store address */

    add mic1_PC, mic1_PC, #1                /* Get the low byte of the address */
    _fetch_

    orr mic1_H, mic1_H, mic1_MBRU
    sub mic1_PC, mic1_PC, #4
    add mic1_PC, mic1_PC, mic1_H
    _fetch_

    b main1

ret:
    cmp mic1_CPP, #0                        /* Check for ret from main (CPP == 0) */
    beq exit                                /* Exit if CPP == 0, else continue on */

    mov mic1_MAR, mic1_CPP                  /* Get the link pointer */
    _read_

    mov mic1_CPP, mic1_MDR                  /* Restore the old CPP */

    add mic1_MAR, mic1_MAR, #4              /* Get the PC */
    _read_

    mov mic1_PC, mic1_MDR                   /* Restore the old PC and get the opcode */
    _fetch_

    add mic1_MAR, mic1_MAR, #4              /* Get LV */
    _read_

    mov mic1_MAR, mic1_LV                   /* Drop the local stack */
    mov mic1_SP, mic1_MAR

    mov mic1_LV, mic1_MDR                   /* Restore the old LV */

    mov mic1_MDR, mic1_TOS                  /* Push the return value */
    _write_

    b main1

errorOpcode:
    ldr r0, addr_errorOpcodeMsg
    bl printf
    b exitError

errorArg:
    ldr r0, addr_errorArgMsg
    bl printf
    b exitError

errorFile:
    ldr r0, addr_errorFileMsg
    bl printf
    b exitError

exit:
    ldr r0, addr_format
    mov r1, mic1_TOS                /* Return what is at the top of the stack */
    bl printf
    mov r0, #0
    pop {lr}
    bx lr

/* Exits after an error is called, doesn't print out the TOS */
exitError:
    mov r0, #0
    pop {lr}
    bx lr

/*
============================= ADDRESSES =============================
 */
.balign 4
addr_array: .word array

.balign 4
addr_currentIndex: .word currentIndex

.balign 4
addr_format: .word format

.balign 4
addr_errorOpcodeMsg: .word errorOpcodeMsg

.balign 4
addr_errorArgMsg: .word errorArgMsg

.balign 4
addr_errorFileMsg: .word errorFileMsg

/* TODO: couldn't figure out how to fix 10factorial... (probably error in jsr/ret) */