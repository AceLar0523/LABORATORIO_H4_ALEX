<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Alerta extends Model
{
    use HasFactory;

    protected $table = 'alertas';

    protected $fillable = [
        'paso_id',
        'tipo',
        'mensaje',
        'atendida',
    ];

    protected $casts = [
        'atendida' => 'boolean',
    ];

    public function paso()
    {
        return $this->belongsTo(Paso::class);
    }
}

