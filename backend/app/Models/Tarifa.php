<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Tarifa extends Model
{
    use HasFactory;

    protected $table = 'tarifas';

    protected $fillable = [
        'categoria',
        'ejes',
        'monto',
    ];

    protected $casts = [
        'ejes' => 'integer',
        'monto' => 'decimal:2',
    ];
}

